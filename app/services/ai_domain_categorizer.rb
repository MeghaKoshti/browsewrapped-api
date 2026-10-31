# Second pass after the rule-based UrlCategorizer: finds the most-visited
# domains still marked "Other", reuses cached answers from DomainCategory and
# asks the LLM (one batched call) only about domains it has never seen.
#
# Fail-safe: with the feature off, no API key, a timeout or a bad response,
# the analysis simply keeps "Other" for those domains.
#
#   result = AiDomainCategorizer.new(entries).call
#   result.overrides      # => { "example.dev" => "Programming" }
#   result.ai_classified  # => number of domains moved out of "Other" by the AI
#
# Private hosts (IP addresses, localhost, intranet names like "wiki" or
# "jira.corp") are never sent: they say more about the user's employer than
# about their interests.
class AiDomainCategorizer
  Result = Data.define(:overrides, :ai_classified)
  EMPTY  = Result.new(overrides: {}, ai_classified: 0)

  PRIVATE_SUFFIXES = %w[.local .internal .corp .lan .localhost .home .intranet].freeze

  def self.enabled?
    ENV.fetch("AI_CATEGORISATION", "on") != "off"
  end

  def self.max_domains
    ENV.fetch("AI_CATEGORISATION_MAX_DOMAINS", 50).to_i
  end

  # time_budget: total seconds the LLM call may take (nil = the classifier's defaults).
  def initialize(entries, classifier: nil, categorizer: UrlCategorizer.new, time_budget: nil)
    @entries     = entries
    @categorizer = categorizer
    @classifier  = classifier || (LlmDomainClassifier.new(time_budget: time_budget) if LlmDomainClassifier.available?)
  end

  # True for hosts that must never leave the server.
  def self.private_host?(host)
    host = host.to_s.downcase.delete_suffix(".")
    return true if host.empty? || !host.include?(".") # localhost, intranet single labels
    return true if host.match?(/\A[\d.]+\z/) || host.include?(":") || host.start_with?("[") # IPv4 / IPv6

    PRIVATE_SUFFIXES.any? { |suffix| host.end_with?(suffix) }
  end

  def call
    return EMPTY unless self.class.enabled?

    domains = uncategorised_domains
    return EMPTY if domains.empty?

    cached = DomainCategory.where(domain: domains).index_by(&:domain)
    classify_new(domains - cached.keys).each { |row| cached[row.domain] = row }

    known = cached.values.reject { |row| row.category == "Other" }
    Result.new(
      overrides:     known.to_h { |row| [ row.domain, row.category ] },
      ai_classified: known.count { |row| row.source == "ai" }
    )
  rescue => e
    Rails.logger.warn("AI categorisation skipped: #{e.class}: #{e.message}")
    EMPTY
  end

  private

  # Unique "Other" domains, most visited first, capped at max_domains.
  def uncategorised_domains
    counts = Hash.new(0)
    @entries.each do |entry|
      next unless @categorizer.categorize(entry[:url]) == "Other"

      domain = UrlCategorizer.domain_for(entry[:url])
      counts[domain] += entry[:visit_count].to_i.clamp(1..) if domain && !self.class.private_host?(domain)
    end
    counts.sort_by { |domain, visits| [ -visits, domain ] }.first(self.class.max_domains).map(&:first)
  end

  def classify_new(domains)
    return [] if domains.empty? || @classifier.nil?

    answers = @classifier.classify(domains)
    answers.filter_map do |domain, answer|
      DomainCategory.create_or_find_by!(domain: domain) do |row|
        row.category   = answer[:category]
        row.confidence = answer[:confidence]
        row.source     = "ai"
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("Skipping AI category for #{domain}: #{e.message}")
      nil
    end
  rescue LlmDomainClassifier::Error => e
    Rails.logger.warn("LLM domain classification failed: #{e.message}")
    []
  end
end
