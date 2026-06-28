require "csv"
require "cgi"

class HistoryParser
  def self.parse(content)
    new(content).parse
  end

  def initialize(content)
    @content = content.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
  end

  def parse
    try_json || try_csv || raise("Unsupported format. Please upload a Chrome Takeout JSON, extension export JSON, or CSV file.")
  end

  private

  def try_json
    data = JSON.parse(@content)

    if data.is_a?(Hash) && data["Browser History"].is_a?(Array)
      return parse_chrome_takeout(data["Browser History"])
    end

    if data.is_a?(Array) && data.first.is_a?(Hash) && data.first["url"]
      return parse_generic_array(data)
    end

    nil
  rescue JSON::ParserError
    nil
  end

  def parse_chrome_takeout(entries)
    entries.filter_map do |e|
      url = e["url"]
      next unless url&.start_with?("http")

      visited_at = parse_chrome_time(e["time_usec"])
      { url: url, title: e["title"].to_s, visited_at: visited_at, visit_count: 1 }
    end
  end

  def parse_generic_array(entries)
    entries.filter_map do |e|
      url = e["url"]
      next unless url&.start_with?("http")

      raw_time = e["visitTime"] || e["visit_time"] || e["lastVisitTime"] ||
                 e["last_visit_time"] || e["time"] || e["timestamp"]
      visited_at = parse_timestamp(raw_time)
      visit_count = (e["visitCount"] || e["visit_count"] || 1).to_i

      { url: url, title: e["title"].to_s, visited_at: visited_at, visit_count: [ visit_count, 1 ].max }
    end
  end

  def try_csv
    rows = CSV.parse(@content, headers: true, skip_blanks: true)
    return nil if rows.empty? || rows.headers.compact.empty?

    url_col = rows.headers.find { |h| h&.downcase =~ /\burl\b/ }
    return nil unless url_col

    title_col = rows.headers.find { |h| h&.downcase =~ /title/ }
    time_col  = rows.headers.find { |h| h&.downcase =~ /time|date|visit/ }
    count_col = rows.headers.find { |h| h&.downcase =~ /count/ }

    rows.filter_map do |row|
      url = row[url_col]
      next unless url&.start_with?("http")

      {
        url: url,
        title: title_col ? row[title_col].to_s : "",
        visited_at: time_col ? parse_timestamp(row[time_col]) : nil,
        visit_count: count_col ? [ row[count_col].to_i, 1 ].max : 1
      }
    end
  rescue CSV::MalformedCSVError
    nil
  end

  def parse_chrome_time(value)
    return nil unless value
    usec = value.to_i
    # Try as Unix microseconds first
    t = Time.at(usec / 1_000_000.0).utc
    return t if t.year.between?(2000, 2035)
    # Try as Windows FILETIME (microseconds since Jan 1, 1601)
    t = Time.at(usec / 1_000_000.0 - 11_644_473_600).utc
    t.year.between?(2000, 2035) ? t : nil
  rescue
    nil
  end

  def parse_timestamp(value)
    return nil unless value
    s = value.to_s.strip
    # 13-digit milliseconds
    return Time.at(s.to_i / 1000.0).utc if s =~ /^\d{13}$/
    # 10-digit seconds
    return Time.at(s.to_i).utc if s =~ /^\d{10}$/
    Time.parse(s).utc
  rescue
    nil
  end
end
