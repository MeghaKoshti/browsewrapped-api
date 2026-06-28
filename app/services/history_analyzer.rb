require "uri"
require "cgi"
require "set"

class HistoryAnalyzer
  SEARCH_QUERY_PARAMS = {
    /google\.com\/search/ => "q",
    /bing\.com\/search/ => "q",
    /duckduckgo\.com/ => "q",
    /search\.yahoo\.com/ => "p",
    /startpage\.com/ => "query",
  }.freeze

  def initialize(entries)
    @entries = entries
    @categorizer = UrlCategorizer.new
  end

  def analyze
    return empty_result if @entries.empty?

    {
      summary: build_summary,
      topics: build_topics,
      daily_pattern: build_daily_pattern,
      weekly_pattern: build_weekly_pattern,
      monthly_trends: build_monthly_trends,
      top_domains: build_top_domains,
      top_searches: build_top_searches,
      knowledge_graph: build_knowledge_graph,
    }
  end

  private

  def categorized
    @categorized ||= @entries.map { |e| e.merge(topic: @categorizer.categorize(e[:url])) }
  end

  def timed
    @timed ||= categorized.select { |e| e[:visited_at] }
  end

  def has_timestamps?
    @has_timestamps ||= timed.size >= [ @entries.size * 0.05, 10 ].min
  end

  def build_summary
    total_visits = @entries.sum { |e| e[:visit_count] }
    unique_domains = @entries.filter_map { |e| extract_domain(e[:url]) }.uniq.size

    dates = timed.map { |e| e[:visited_at].to_date }
    top_topic_entry = build_topics.reject { |t| t[:name] == "Search" }.first
    top_domain_entry = build_top_domains.first

    {
      total_visits: total_visits,
      unique_domains: unique_domains,
      date_range: dates.any? ? { start: dates.min.iso8601, end: dates.max.iso8601 } : nil,
      total_days: dates.any? ? (dates.max - dates.min + 1).to_i : nil,
      top_topic: top_topic_entry&.dig(:name) || "Unknown",
      top_domain: top_domain_entry&.dig(:domain) || "Unknown",
      has_timestamps: has_timestamps?,
    }
  end

  def build_topics
    counts = Hash.new(0)
    categorized.each { |e| counts[e[:topic]] += e[:visit_count] }
    total = counts.values.sum.to_f

    counts.map do |name, visits|
      {
        name: name,
        visits: visits,
        percentage: ((visits / total) * 100).round(1),
        color: UrlCategorizer::CATEGORY_COLORS[name] || "#475569",
      }
    end.sort_by { |t| -t[:visits] }
  end

  def build_daily_pattern
    hours = Array.new(24) { |h| { hour: h, visits: 0 } }
    return hours unless has_timestamps?

    timed.each do |e|
      h = e[:visited_at].hour
      hours[h][:visits] += e[:visit_count]
    end
    hours
  end

  def build_weekly_pattern
    return [] unless has_timestamps?

    day_names = %w[Sun Mon Tue Wed Thu Fri Sat]
    counts = Array.new(7, 0)
    timed.each { |e| counts[e[:visited_at].wday] += e[:visit_count] }
    counts.each_with_index.map { |v, i| { day: day_names[i], visits: v } }
  end

  def build_monthly_trends
    return { labels: [], data: [] } unless has_timestamps?

    top_topics = build_topics
      .reject { |t| t[:name] == "Search" }
      .first(6)
      .map { |t| t[:name] }

    monthly = Hash.new { |h, k| h[k] = Hash.new(0) }
    timed.each do |e|
      next unless top_topics.include?(e[:topic])
      month = e[:visited_at].strftime("%Y-%m")
      monthly[month][e[:topic]] += e[:visit_count]
    end

    data = monthly.sort.map do |month, topic_counts|
      row = { month: month }
      top_topics.each { |t| row[t] = topic_counts[t] }
      row
    end

    { labels: top_topics, data: data }
  end

  def build_top_domains
    counts = Hash.new(0)
    @entries.each { |e| counts[extract_domain(e[:url])] += e[:visit_count] }
    counts.delete("unknown")

    counts.sort_by { |_, v| -v }.first(20).map do |domain, visits|
      topic = @categorizer.categorize("https://#{domain}")
      { domain: domain, visits: visits, topic: topic, color: UrlCategorizer::CATEGORY_COLORS[topic] || "#475569" }
    end
  end

  def build_top_searches
    counts = Hash.new(0)

    @entries.each do |entry|
      url = entry[:url]
      SEARCH_QUERY_PARAMS.each do |pattern, param|
        next unless url =~ pattern
        begin
          uri = URI.parse(url)
          query = CGI.parse(uri.query || "")[param]&.first
          next unless query && query.length >= 3
          q = CGI.unescape(query).gsub("+", " ").strip
          counts[q] += entry[:visit_count] if q.length >= 3
        rescue
          next
        end
      end
    end

    counts.sort_by { |_, v| -v }.first(30).map { |q, c| { query: q, count: c } }
  end

  def build_knowledge_graph
    top_topics = build_topics.first(12)
    topic_names = top_topics.map { |t| t[:name] }.to_set

    nodes = top_topics.map do |t|
      {
        id: t[:name],
        label: t[:name],
        size: Math.sqrt(t[:visits]).ceil,
        visits: t[:visits],
        color: t[:color],
      }
    end

    edges = if has_timestamps? && timed.size > 20
      build_edges_by_cooccurrence(topic_names)
    else
      build_edges_by_domain_overlap(topic_names)
    end

    { nodes: nodes, edges: edges }
  end

  def build_edges_by_cooccurrence(topic_names)
    sorted = timed.sort_by { |e| e[:visited_at] }
    co = Hash.new(0)
    sorted.each_cons(8) do |group|
      topics = group.map { |e| e[:topic] }.select { |t| topic_names.include?(t) }.uniq
      topics.combination(2) { |a, b| co[[ a, b ].sort.join("|")] += 1 }
    end
    co.sort_by { |_, w| -w }.first(20).filter_map do |key, weight|
      a, b = key.split("|")
      { source: a, target: b, weight: weight } if topic_names.include?(a) && topic_names.include?(b)
    end
  end

  def build_edges_by_domain_overlap(topic_names)
    topic_domains = Hash.new { |h, k| h[k] = Set.new }
    categorized.each { |e| topic_domains[e[:topic]] << extract_domain(e[:url]) }

    edges = []
    topic_names.to_a.combination(2) do |a, b|
      common = (topic_domains[a] & topic_domains[b]).size
      edges << { source: a, target: b, weight: common } if common > 0
    end
    edges.sort_by { |e| -e[:weight] }.first(15)
  end

  def extract_domain(url)
    return "unknown" unless url
    URI.parse(url).host&.downcase&.sub(/^www\./, "") || "unknown"
  rescue URI::InvalidURIError
    "unknown"
  end

  def empty_result
    {
      summary: { total_visits: 0, unique_domains: 0, has_timestamps: false },
      topics: [],
      daily_pattern: Array.new(24) { |h| { hour: h, visits: 0 } },
      weekly_pattern: [],
      monthly_trends: { labels: [], data: [] },
      top_domains: [],
      top_searches: [],
      knowledge_graph: { nodes: [], edges: [] },
    }
  end
end
