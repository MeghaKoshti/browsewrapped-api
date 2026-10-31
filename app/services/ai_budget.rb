# A hard daily ceiling on how many domains are sent to the LLM, so a traffic
# spike (or abuse) can't run up the Gemini bill. Counted per UTC day in
# Rails.cache (Solid Cache in production, shared by every worker).
#
#   allowed = AiBudget.take(50)  # => how many of the 50 may be sent now (0..50)
module AiBudget
  module_function

  def daily_limit
    ENV.fetch("AI_DAILY_DOMAIN_BUDGET", 2_000).to_i
  end

  def used_today
    store.read(key).to_i
  end

  def remaining_today
    [ daily_limit - used_today, 0 ].max
  end

  # Reserves up to `count` domains from today's budget and returns how many
  # were granted. Logs once a day when the budget runs out.
  def take(count)
    granted = [ count, remaining_today ].min
    store.increment(key, granted, expires_in: 2.days) if granted.positive?
    log_exhausted_once if granted < count
    granted
  end

  def log_exhausted_once
    first = store.write("#{key}:logged", true, unless_exist: true, expires_in: 2.days)
    Rails.logger.warn("AI daily domain budget of #{daily_limit} used up; skipping the LLM until tomorrow (UTC)") if first
  end

  def key
    "ai_domains_used:#{Time.now.utc.to_date.iso8601}"
  end

  # Tests swap in a real store (the test cache is a null store), as for rate limits.
  def store
    Rails.configuration.x.rate_limit_store.presence || Rails.cache
  end
end
