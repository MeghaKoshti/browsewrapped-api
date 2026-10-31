require "test_helper"

class HistoryAnalyzerTest < ActiveSupport::TestCase
  test "returns an empty report when there are no entries" do
    result = HistoryAnalyzer.new([]).analyze

    assert_equal 0, result[:summary][:total_visits]
    assert_equal "polymath", result[:persona][:id]
    assert_empty result[:topics]
  end

  test "report includes every section the frontend expects" do
    result = HistoryAnalyzer.new([ entry("https://github.com") ]).analyze

    expected = %i[summary persona topics time_by_topic daily_pattern weekly_pattern
                  monthly_trends heatmap activity_calendar sessions streaks topic_momentum period_comparison
                  top_domains top_pages top_searches chrome_searches intent knowledge_graph]
    assert_equal expected.sort, result.keys.sort
  end

  test "summary counts visits and unique domains" do
    entries = [
      entry("https://github.com/a", visit_count: 2),
      entry("https://www.github.com/b"),
      entry("https://dev.to/post")
    ]

    summary = HistoryAnalyzer.new(entries).analyze[:summary]

    assert_equal 4, summary[:total_visits]
    assert_equal 2, summary[:unique_domains]
    assert_equal "Programming", summary[:top_topic]
    assert_equal "github.com", summary[:top_domain]
  end

  test "topic percentages are weighted by visit count" do
    entries = [
      entry("https://github.com", visit_count: 3),
      entry("https://youtube.com/watch?v=1", visit_count: 1)
    ]

    topics = HistoryAnalyzer.new(entries).analyze[:topics]

    assert_equal "Programming", topics.first[:name]
    assert_equal 75.0, topics.first[:percentage]
    assert_equal 25.0, topics.last[:percentage]
  end

  test "a mostly-programming history gets The Builder persona" do
    entries = Array.new(20) { |i| entry("https://github.com/repo/#{i}") } +
              Array.new(5) { |i| entry("https://youtube.com/watch?v=#{i}") }

    assert_equal "builder", HistoryAnalyzer.new(entries).analyze[:persona][:id]
  end

  test "longest streak counts consecutive active days" do
    days = [ 1, 2, 3, 7, 8 ].map { |d| Time.utc(2026, 6, d, 12) }
    entries = days.flat_map { |t| Array.new(3) { |i| entry("https://github.com/#{i}", visited_at: t) } }

    streaks = HistoryAnalyzer.new(entries).analyze[:streaks]

    assert_equal 3, streaks[:longest]
    assert_equal 5, streaks[:total_active_days]
  end

  test "analyzes the bundled sample file without errors" do
    entries = HistoryParser.parse(File.read(Rails.root.join("sample/sample_history.json")))

    result = HistoryAnalyzer.new(entries).analyze

    assert result[:summary][:has_timestamps]
    assert_not_empty result[:knowledge_graph][:nodes]
    assert_equal 24, result[:daily_pattern].size
  end

  # ─── period_comparison ────────────────────────────────────────────────────

  # 60 days (Aug 1 – Sep 29), so both windows are the full 30 days.
  def comparison_entries
    [
      entry("https://github.com/a", visited_at: Time.utc(2026, 8, 1, 10), visit_count: 2),
      entry("https://github.com/b", visited_at: Time.utc(2026, 8, 10, 10)),
      entry("https://github.com/c", visited_at: Time.utc(2026, 8, 10, 10, 12)),
      entry("https://github.com/d", visited_at: Time.utc(2026, 9, 1, 10), visit_count: 2),
      entry("https://huggingface.co/models", visited_at: Time.utc(2026, 9, 15, 10), visit_count: 3),
      entry("https://github.com/e", visited_at: Time.utc(2026, 9, 29, 10)),
      entry("https://github.com/f", visited_at: Time.utc(2026, 9, 29, 10, 30))
    ]
  end

  test "period comparison compares the last 30 days with the 30 days before" do
    comparison = HistoryAnalyzer.new(comparison_entries).analyze[:period_comparison]

    assert_equal 30, comparison[:window_days]
    assert_equal({ label: "Last 30 days", from: "2026-08-31", to: "2026-09-29", visits: 7, active_days: 3, hours: 0.5, top_topic: "Programming" },
                 comparison[:current])
    assert_equal({ label: "Previous 30 days", from: "2026-08-01", to: "2026-08-30", visits: 4, active_days: 2, hours: 0.2, top_topic: "Programming" },
                 comparison[:previous])
    assert_equal({ visits_pct: 75.0, active_days_delta: 1, hours_pct: 150.0 }, comparison[:changes])
  end

  test "period comparison topics are sorted by current visits, with a null change for new topics" do
    topics = HistoryAnalyzer.new(comparison_entries).analyze[:period_comparison][:topics]

    assert_equal [
      { topic: "Programming", current: 4, previous: 4, change_pct: 0.0 },
      { topic: "AI & ML",     current: 3, previous: 0, change_pct: nil }
    ], topics
  end

  test "period comparison percentages are null when the previous window is empty" do
    # 121 days → the windows are Aug 31–Sep 29 and Aug 1–30; the June visit is in neither.
    entries = [
      entry("https://github.com/a", visited_at: Time.utc(2026, 6, 1, 10)),
      entry("https://github.com/b", visited_at: Time.utc(2026, 9, 29, 10), visit_count: 2)
    ]

    comparison = HistoryAnalyzer.new(entries).analyze[:period_comparison]

    assert_equal 0, comparison.dig(:previous, :visits)
    assert_nil comparison.dig(:previous, :top_topic)
    assert_equal({ visits_pct: nil, active_days_delta: 1, hours_pct: nil }, comparison[:changes])
    assert_equal [ { topic: "Programming", current: 2, previous: 0, change_pct: nil } ], comparison[:topics]
  end

  test "period comparison keeps at most 8 topics and only topic names" do
    domains = %w[github.com huggingface.co youtube.com reddit.com bbc.com figma.com
                 wikipedia.org coursera.org amazon.com notion.so]
    entries = domains.flat_map.with_index do |domain, i|
      [ entry("https://#{domain}/x", visited_at: Time.utc(2026, 8, 1, 10), visit_count: i + 1),
        entry("https://#{domain}/y", visited_at: Time.utc(2026, 8, 30, 10)) ]
    end

    topics = HistoryAnalyzer.new(entries).analyze[:period_comparison][:topics]

    # 10 topics; the two with the fewest visits overall (Programming, AI & ML) drop out.
    assert_equal 8, topics.size
    assert_not_includes topics.map { |t| t[:topic] }, "Programming"
    assert topics.all? { |t| t.keys == %i[topic current previous change_pct] }
    assert_no_match(/\.(com|org|so|co)\b/, topics.to_json)
  end

  test "period comparison is null for histories shorter than 14 days" do
    entries = [
      entry("https://github.com/a", visited_at: Time.utc(2026, 6, 1, 10)),
      entry("https://github.com/b", visited_at: Time.utc(2026, 6, 13, 10))
    ]

    assert_nil HistoryAnalyzer.new(entries).analyze[:period_comparison]
  end

  test "period comparison starts at exactly 14 days with 7-day windows" do
    entries = [
      entry("https://github.com/a", visited_at: Time.utc(2026, 6, 1, 10)),
      entry("https://github.com/b", visited_at: Time.utc(2026, 6, 14, 10))
    ]

    comparison = HistoryAnalyzer.new(entries).analyze[:period_comparison]

    assert_equal 7, comparison[:window_days]
    assert_equal "Last 7 days", comparison.dig(:current, :label)
  end

  test "period comparison is null without visits or timestamps" do
    assert_nil HistoryAnalyzer.new([]).analyze[:period_comparison]
    assert_nil HistoryAnalyzer.new([ entry("https://github.com", visited_at: nil) ]).analyze[:period_comparison]
  end

  test "the bundled sample spans enough days for a 30-day comparison" do
    entries = HistoryParser.parse(File.read(Rails.root.join("sample/sample_history.json")))

    comparison = HistoryAnalyzer.new(entries).analyze[:period_comparison]

    assert_equal 30, comparison[:window_days]
    assert_operator comparison.dig(:current, :visits), :>, 0
    assert_operator comparison.dig(:previous, :visits), :>, 0
  end
end
