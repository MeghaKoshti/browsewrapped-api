require "test_helper"

class ReportSanitizerTest < ActiveSupport::TestCase
  setup do
    entries = HistoryParser.parse(File.read(Rails.root.join("sample/sample_history.json")))
    @report = HistoryAnalyzer.new(entries).analyze
    @report[:meta] = { total_entries_parsed: entries.size, source: "upload", processed_at: Time.current.iso8601, analysis_id: "abc" }
    @shared = ReportSanitizer.call(@report)
  end

  test "keeps aggregated sections" do
    %w[summary persona topics daily_pattern heatmap knowledge_graph].each do |key|
      assert @shared.key?(key), "expected #{key} to be kept"
    end
  end

  test "removes pages, titles, searches and domains" do
    %w[top_pages top_searches chrome_searches top_domains].each do |key|
      assert_not @shared.key?(key), "expected #{key} to be removed"
    end
    assert_not @shared["summary"].key?("top_domain")
  end

  test "leaves no URLs, page titles, search queries or domains anywhere in the output" do
    json = @shared.to_json

    assert_no_match(%r{https?://}, json)
    @report[:top_pages].each   { |page| assert_not_includes json, page[:title] if page[:title].present? }
    @report[:top_searches].each { |search| assert_not_includes json, search[:query] }
    @report[:top_domains].each { |domain| assert_not_includes json, "\"#{domain[:domain]}\"" }
  end

  test "keeps only safe meta fields and marks the report as shared" do
    assert_equal true, @shared.dig("meta", "shared")
    assert_not @shared["meta"].key?("analysis_id")
  end

  test "drops unknown sections" do
    assert_not ReportSanitizer.call({ "summary" => {}, "secret" => "x" }).key?("secret")
  end

  test "keeps the period comparison with topic names only" do
    comparison = @shared["period_comparison"]

    assert_equal @report[:period_comparison].deep_stringify_keys, comparison
    assert_equal %w[topic current previous change_pct], comparison["topics"].first.keys
  end

  test "drops anything unexpected inside the period comparison" do
    report = {
      "period_comparison" => {
        "window_days" => 30, "secret" => "x",
        "current"  => { "visits" => 5, "top_domain" => "secret.example" },
        "previous" => { "visits" => 4 },
        "changes"  => { "visits_pct" => 25.0, "domains" => [ "secret.example" ] },
        "topics"   => [ { "topic" => "Programming", "current" => 5, "url" => "https://secret.example/page" }, "junk" ]
      }
    }

    shared = ReportSanitizer.call(report)["period_comparison"]

    assert_not_includes shared.to_json, "secret"
    assert_equal({ "visits" => 5 }, shared["current"])
    assert_equal [ { "topic" => "Programming", "current" => 5 } ], shared["topics"]
  end

  test "keeps a null period comparison as null" do
    shared = ReportSanitizer.call({ "period_comparison" => nil })

    assert shared.key?("period_comparison")
    assert_nil shared["period_comparison"]
  end
end
