require "net/http"
require "json"
require "uri"

# Classifies domain names into BrowseWrapped's existing categories with one
# batched LLM call (Google Gemini, free tier).
#
# Privacy: only bare domain names are sent, never URLs, page titles or searches.
#
#   LlmDomainClassifier.new.classify(%w[example.dev foo.io])
#   # => { "example.dev" => { category: "Programming", confidence: 0.9 }, ... }
#
# The transport (prompt -> response text) is injectable so tests never call the API.
class LlmDomainClassifier
  class Error < StandardError; end

  ENDPOINT      = "https://generativelanguage.googleapis.com/v1beta/models".freeze
  OPEN_TIMEOUT  = 5
  READ_TIMEOUT  = 20

  def self.available?
    ENV["GEMINI_API_KEY"].present?
  end

  def self.categories
    UrlCategorizer::CATEGORY_COLORS.keys - [ "Search" ]
  end

  def initialize(transport: nil, api_key: ENV["GEMINI_API_KEY"], model: ENV.fetch("GEMINI_MODEL", "gemini-2.5-flash"))
    @api_key   = api_key
    @model     = model
    @transport = transport || method(:gemini_request)
  end

  # Returns { domain => { category:, confidence: } } for every requested domain.
  # Unknown or missing answers become "Other". Raises Error on transport/parse failure.
  def classify(domains)
    domains = domains.map(&:to_s).uniq
    return {} if domains.empty?

    parse(@transport.call(prompt_for(domains)), domains)
  end

  def prompt_for(domains)
    <<~PROMPT
      You categorise websites by their domain name only.
      Allowed categories (use these exact strings, nothing else): #{self.class.categories.join(", ")}.
      Use "Other" when you are not reasonably sure.
      Return ONLY a JSON array, one object per domain:
      [{"domain": "<domain>", "category": "<category>", "confidence": <number 0-1>}]

      Domains:
      #{domains.join("\n")}
    PROMPT
  end

  def parse(text, domains)
    rows = JSON.parse(text.to_s)
    raise Error, "Expected a JSON array" unless rows.is_a?(Array)

    answers = rows.each_with_object({}) do |row, acc|
      next unless row.is_a?(Hash) && domains.include?(row["domain"].to_s)

      category = self.class.categories.include?(row["category"]) ? row["category"] : "Other"
      confidence = row["confidence"].is_a?(Numeric) ? row["confidence"].to_f.clamp(0.0, 1.0) : nil
      acc[row["domain"].to_s] = { category: category, confidence: confidence }
    end

    domains.index_with { |d| answers[d] || { category: "Other", confidence: nil } }
  rescue JSON::ParserError => e
    raise Error, "LLM returned invalid JSON: #{e.message}"
  end

  private

  def gemini_request(prompt)
    raise Error, "GEMINI_API_KEY is not set" if @api_key.blank?

    uri = URI("#{ENDPOINT}/#{@model}:generateContent")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"]   = "application/json"
    request["x-goog-api-key"] = @api_key
    request.body = JSON.generate(
      contents: [ { parts: [ { text: prompt } ] } ],
      generationConfig: { temperature: 0, responseMimeType: "application/json" }
    )

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
      http.request(request)
    end
    raise Error, "Gemini HTTP #{response.code}" unless response.code.to_i == 200

    JSON.parse(response.body).dig("candidates", 0, "content", "parts", 0, "text").presence ||
      raise(Error, "Empty Gemini response")
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
    raise Error, "Gemini request failed: #{e.class}"
  end
end
