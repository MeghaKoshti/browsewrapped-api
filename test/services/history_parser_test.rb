require "test_helper"

class HistoryParserTest < ActiveSupport::TestCase
  test "parses a Chrome Takeout export" do
    json = {
      "Browser History" => [
        { "url" => "https://github.com/rails/rails", "title" => "Rails", "time_usec" => 1_780_000_000_000_000 },
        { "url" => "chrome://settings", "title" => "Settings", "time_usec" => 1_780_000_000_000_000 }
      ]
    }.to_json

    entries = HistoryParser.parse(json)

    assert_equal 1, entries.size, "non-http URLs should be skipped"
    assert_equal "https://github.com/rails/rails", entries.first[:url]
    assert_equal "Rails", entries.first[:title]
    assert_equal 2026, entries.first[:visited_at].year
    assert_equal 1, entries.first[:visit_count]
  end

  test "parses a JSON array export with millisecond timestamps" do
    json = [
      { "url" => "https://chatgpt.com/", "title" => "ChatGPT", "visitTime" => 1_786_812_063_000, "visitCount" => 3 }
    ].to_json

    entry = HistoryParser.parse(json).first

    assert_equal "https://chatgpt.com/", entry[:url]
    assert_equal 3, entry[:visit_count]
    assert_kind_of Time, entry[:visited_at]
  end

  test "never returns a visit count below 1" do
    json = [ { "url" => "https://example.com", "visitCount" => 0 } ].to_json

    assert_equal 1, HistoryParser.parse(json).first[:visit_count]
  end

  test "parses a CSV file and detects columns by header name" do
    csv = <<~CSV
      URL,Page Title,Visit Time,Visit Count
      https://stackoverflow.com/questions/1,Question,2026-06-01 10:00:00,2
      not-a-url,Junk,2026-06-01 10:00:00,1
    CSV

    entries = HistoryParser.parse(csv)

    assert_equal 1, entries.size
    assert_equal "Question", entries.first[:title]
    assert_equal 2, entries.first[:visit_count]
    assert_equal Time.utc(2026, 6, 1, 10), entries.first[:visited_at]
  end

  test "reads CSV timestamps without an offset as UTC and keeps explicit offsets" do
    csv = <<~CSV
      URL,Visit Time
      https://example.com/a,2026-06-01 10:00:00
      https://example.com/b,2026-06-01T10:00:00+05:30
    CSV

    a, b = HistoryParser.parse(csv)

    assert_equal Time.utc(2026, 6, 1, 10), a[:visited_at]
    assert_equal Time.utc(2026, 6, 1, 4, 30), b[:visited_at]
  end

  test "keeps entries with unreadable timestamps but sets visited_at to nil" do
    json = [ { "url" => "https://example.com", "visitTime" => "not a date" } ].to_json

    assert_nil HistoryParser.parse(json).first[:visited_at]
  end

  test "raises a helpful error for unsupported content" do
    error = assert_raises(HistoryParser::UnsupportedFormatError) { HistoryParser.parse("just some text") }

    assert_match(/Unsupported format/, error.message)
  end

  test "parses the bundled sample file" do
    content = File.read(Rails.root.join("sample/sample_history.json"))

    entries = HistoryParser.parse(content)

    assert_operator entries.size, :>, 1000
    assert entries.all? { |e| e[:url].start_with?("http") }
  end
end
