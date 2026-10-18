# Strips anything that could identify what someone actually browsed before a
# report is shared publicly. Uses an allowlist, so any new report section stays
# private until it is added here on purpose.
#
# Kept:     aggregated stats (persona, topics, charts, patterns, streaks...).
# Removed:  top_pages (URLs + titles), top_searches / chrome_searches (queries),
#           top_domains and summary.top_domain (which sites), and unknown keys.
class ReportSanitizer
  SHAREABLE_SECTIONS = %w[
    summary persona topics time_by_topic daily_pattern weekly_pattern
    monthly_trends heatmap activity_calendar sessions streaks topic_momentum
    intent knowledge_graph
  ].freeze

  PRIVATE_SUMMARY_KEYS = %w[top_domain].freeze
  SHAREABLE_META_KEYS  = %w[total_entries_parsed source processed_at ai_classified_domains].freeze

  def self.call(report)
    new(report).call
  end

  def initialize(report)
    @report = report.to_h.deep_stringify_keys
  end

  def call
    shared = @report.slice(*SHAREABLE_SECTIONS)
    shared["summary"] = shared["summary"].except(*PRIVATE_SUMMARY_KEYS) if shared["summary"].is_a?(Hash)
    shared["meta"] = (@report["meta"].is_a?(Hash) ? @report["meta"].slice(*SHAREABLE_META_KEYS) : {}).merge("shared" => true)
    shared
  end
end
