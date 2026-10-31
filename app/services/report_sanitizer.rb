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
    intent knowledge_graph period_comparison
  ].freeze

  PRIVATE_SUMMARY_KEYS = %w[top_domain].freeze
  SHAREABLE_META_KEYS  = %w[total_entries_parsed source processed_at ai_classified_domains].freeze

  # period_comparison holds topic names and counts only; anything else a client
  # sends inside it is dropped.
  PERIOD_KEYS        = %w[label from to visits active_days hours top_topic].freeze
  PERIOD_CHANGE_KEYS = %w[visits_pct active_days_delta hours_pct].freeze
  PERIOD_TOPIC_KEYS  = %w[topic current previous change_pct].freeze

  def self.call(report)
    new(report).call
  end

  def initialize(report)
    @report = report.to_h.deep_stringify_keys
  end

  def call
    shared = @report.slice(*SHAREABLE_SECTIONS)
    shared["summary"] = shared["summary"].except(*PRIVATE_SUMMARY_KEYS) if shared["summary"].is_a?(Hash)
    shared["period_comparison"] = sanitize_period_comparison(shared["period_comparison"]) if shared.key?("period_comparison")
    shared["meta"] = (@report["meta"].is_a?(Hash) ? @report["meta"].slice(*SHAREABLE_META_KEYS) : {}).merge("shared" => true)
    shared
  end

  private

  def sanitize_period_comparison(comparison)
    return nil unless comparison.is_a?(Hash)

    {
      "window_days" => comparison["window_days"],
      "current"     => slice_hash(comparison["current"], PERIOD_KEYS),
      "previous"    => slice_hash(comparison["previous"], PERIOD_KEYS),
      "changes"     => slice_hash(comparison["changes"], PERIOD_CHANGE_KEYS),
      "topics"      => Array(comparison["topics"]).filter_map { |t| slice_hash(t, PERIOD_TOPIC_KEYS) }
    }
  end

  def slice_hash(value, keys)
    value.slice(*keys) if value.is_a?(Hash)
  end
end
