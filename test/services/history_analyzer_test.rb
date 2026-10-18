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
                  monthly_trends heatmap activity_calendar sessions streaks topic_momentum
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
end
