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

  SEARCH_URL_PATTERNS = [
    /google\.com\/search/, /bing\.com\/search/, /duckduckgo\.com\/\?/,
    /youtube\.com\/results/, /google\.com\/\?q=/, /google\.com\/#q=/,
  ].freeze

  SESSION_GAP_SECS = 30 * 60
  MAX_PAGE_DURATION_USEC = 2 * 3_600_000_000  # cap individual page at 2 hours

  def initialize(entries, chrome_searches: [])
    @entries = entries
    @chrome_searches = chrome_searches
    @categorizer = UrlCategorizer.new
  end

  def analyze
    return empty_result if @entries.empty?

    {
      summary:        build_summary,
      topics:         build_topics,
      time_by_topic:  build_time_by_topic,
      daily_pattern:  build_daily_pattern,
      weekly_pattern: build_weekly_pattern,
      monthly_trends: build_monthly_trends,
      heatmap:        build_heatmap,
      sessions:       sessions_data,
      top_domains:    build_top_domains,
      top_pages:      build_top_pages,
      top_searches:   build_top_searches,
      chrome_searches: build_chrome_searches,
      intent:         build_intent_analysis,
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

  def has_duration_data?
    @has_duration ||= @entries.count { |e| e[:visit_duration].to_i > 0 } > @entries.size * 0.1
  end

  # ─── Memoized session computation ─────────────────────────────────────────

  def sessions_data
    @sessions_data ||= compute_sessions
  end

  def compute_sessions
    unless has_timestamps? && timed.size > 1
      return { total_sessions: 0, avg_duration_minutes: 0, longest_session_minutes: 0, total_hours_browsed: 0 }
    end

    sorted = timed.sort_by { |e| e[:visited_at] }

    sessions = [[sorted.first]]
    sorted.each_cons(2) do |a, b|
      gap = (b[:visited_at] - a[:visited_at]).abs
      gap > SESSION_GAP_SECS ? (sessions << [b]) : (sessions.last << b)
    end

    durations_min = sessions.map do |s|
      if s.size == 1
        dur = s[0][:visit_duration].to_i / 60_000_000.0
        dur > 0.1 ? dur : 0.0
      else
        span = (s.last[:visited_at] - s.first[:visited_at]).to_f / 60
        last_dur = [s.last[:visit_duration].to_i / 60_000_000.0, 30.0].min
        span + last_dur
      end
    end.select { |d| d > 0 }

    total_min = durations_min.sum

    {
      total_sessions:          sessions.size,
      avg_duration_minutes:    durations_min.any? ? (total_min / durations_min.size).round(1) : 0,
      longest_session_minutes: durations_min.max&.round(1) || 0,
      total_hours_browsed:     (total_min / 60.0).round(1),
    }
  end

  # ─── Summary ──────────────────────────────────────────────────────────────

  def build_summary
    total_visits   = @entries.sum { |e| e[:visit_count] }
    unique_domains = @entries.filter_map { |e| extract_domain(e[:url]) }.uniq.size

    dates = timed.map { |e| e[:visited_at].to_date }
    top_topic_entry  = build_topics.reject { |t| t[:name] == "Search" }.first
    top_domain_entry = build_top_domains.first

    total_days = dates.any? ? (dates.max - dates.min + 1).to_i : nil
    sd = sessions_data
    avg_daily = (total_days && total_days > 0 && sd[:total_hours_browsed] > 0) ?
                  ((sd[:total_hours_browsed] * 60) / total_days).round(1) : nil

    peak = build_daily_pattern.max_by { |h| h[:visits] }
    peak_hour = peak&.dig(:visits).to_i > 0 ? fmt_hour(peak[:hour]) : nil

    weekend_visits = timed.count { |e| [0, 6].include?(e[:visited_at].wday) }
    weekend_pct = timed.size > 0 ? ((weekend_visits / timed.size.to_f) * 100).round(1) : 0

    {
      total_visits:        total_visits,
      unique_domains:      unique_domains,
      date_range:          dates.any? ? { start: dates.min.iso8601, end: dates.max.iso8601 } : nil,
      total_days:          total_days,
      top_topic:           top_topic_entry&.dig(:name) || "Unknown",
      top_domain:          top_domain_entry&.dig(:domain) || "Unknown",
      has_timestamps:      has_timestamps?,
      has_duration_data:   has_duration_data?,
      total_hours_browsed: sd[:total_hours_browsed],
      avg_daily_minutes:   avg_daily,
      peak_hour:           peak_hour,
      weekend_pct:         weekend_pct,
    }
  end

  # ─── Topics ───────────────────────────────────────────────────────────────

  def build_topics
    @topics_cache ||= begin
      counts = Hash.new(0)
      categorized.each { |e| counts[e[:topic]] += e[:visit_count] }
      total = counts.values.sum.to_f

      counts.map do |name, visits|
        {
          name:       name,
          visits:     visits,
          percentage: ((visits / total) * 100).round(1),
          color:      UrlCategorizer::CATEGORY_COLORS[name] || "#475569",
        }
      end.sort_by { |t| -t[:visits] }
    end
  end

  # ─── Time by topic ────────────────────────────────────────────────────────

  def build_time_by_topic
    return [] unless has_duration_data?

    topic_usec   = Hash.new(0)
    topic_visits = Hash.new(0)

    categorized.each do |e|
      dur = e[:visit_duration].to_i
      next unless dur > 0
      capped = [dur, MAX_PAGE_DURATION_USEC].min
      topic_usec[e[:topic]]   += capped
      topic_visits[e[:topic]] += 1
    end

    return [] if topic_usec.empty?

    total_usec = topic_usec.values.sum.to_f

    topic_usec.map do |name, usec|
      {
        name:                 name,
        minutes:              (usec / 60_000_000.0).round(1),
        hours:                (usec / 3_600_000_000.0).round(2),
        visits_with_duration: topic_visits[name],
        percentage:           total_usec > 0 ? ((usec / total_usec) * 100).round(1) : 0,
        color:                UrlCategorizer::CATEGORY_COLORS[name] || "#475569",
      }
    end.select { |t| t[:minutes] > 0 }.sort_by { |t| -t[:minutes] }
  end

  # ─── Daily / Weekly ───────────────────────────────────────────────────────

  def build_daily_pattern
    hours = Array.new(24) { |h| { hour: h, visits: 0 } }
    return hours unless has_timestamps?

    timed.each { |e| hours[e[:visited_at].hour][:visits] += e[:visit_count] }
    hours
  end

  def build_weekly_pattern
    return [] unless has_timestamps?

    day_names = %w[Sun Mon Tue Wed Thu Fri Sat]
    counts    = Array.new(7, 0)
    timed.each { |e| counts[e[:visited_at].wday] += e[:visit_count] }
    counts.each_with_index.map { |v, i| { day: day_names[i], visits: v } }
  end

  # ─── Monthly trends ───────────────────────────────────────────────────────

  def build_monthly_trends
    return { labels: [], data: [] } unless has_timestamps?

    top_topics = build_topics
      .reject { |t| t[:name] == "Search" }
      .first(6)
      .map { |t| t[:name] }

    monthly = Hash.new { |h, k| h[k] = Hash.new(0) }
    timed.each do |e|
      next unless top_topics.include?(e[:topic])
      monthly[e[:visited_at].strftime("%Y-%m")][e[:topic]] += e[:visit_count]
    end

    data = monthly.sort.map do |month, topic_counts|
      row = { month: month }
      top_topics.each { |t| row[t] = topic_counts[t] }
      row
    end

    { labels: top_topics, data: data }
  end

  # ─── Heatmap (7 days × 24 hours) ─────────────────────────────────────────

  def build_heatmap
    grid = Array.new(7) { Array.new(24, 0) }
    labels = %w[Sun Mon Tue Wed Thu Fri Sat]

    unless has_timestamps?
      return { grid: grid, max: 0, day_labels: labels }
    end

    timed.each do |e|
      grid[e[:visited_at].wday][e[:visited_at].hour] += e[:visit_count]
    end

    { grid: grid, max: grid.flatten.max, day_labels: labels }
  end

  # ─── Top domains ──────────────────────────────────────────────────────────

  def build_top_domains
    counts = Hash.new(0)
    @entries.each { |e| counts[extract_domain(e[:url])] += e[:visit_count] }
    counts.delete("unknown")

    counts.sort_by { |_, v| -v }.first(20).map do |domain, visits|
      topic = @categorizer.categorize("https://#{domain}")
      { domain: domain, visits: visits, topic: topic, color: UrlCategorizer::CATEGORY_COLORS[topic] || "#475569" }
    end
  end

  # ─── Top individual pages ─────────────────────────────────────────────────

  def build_top_pages
    url_data = Hash.new { |h, k| h[k] = { count: 0, title: nil, duration: 0 } }

    @entries.each do |e|
      url = e[:url].split("#").first rescue e[:url]
      next if SEARCH_URL_PATTERNS.any? { |p| url =~ p }
      url_data[url][:count]    += e[:visit_count]
      url_data[url][:title]    ||= e[:title].presence
      url_data[url][:duration] += e[:visit_duration].to_i
    end

    url_data.sort_by { |_, d| -d[:count] }.first(15).map do |url, d|
      topic  = @categorizer.categorize(url)
      domain = extract_domain(url)
      title  = (d[:title].presence || domain)[0..80]
      dur_min = [d[:duration] / 60_000_000.0, MAX_PAGE_DURATION_USEC / 60_000_000.0].min.round(1)
      {
        url:          url,
        title:        title,
        visits:       d[:count],
        domain:       domain,
        duration_min: dur_min > 0 ? dur_min : nil,
        topic:        topic,
        color:        UrlCategorizer::CATEGORY_COLORS[topic] || "#475569",
      }
    end
  end

  # ─── Searches ─────────────────────────────────────────────────────────────

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

  def build_chrome_searches
    return [] if @chrome_searches.empty?

    counts = Hash.new(0)
    @chrome_searches.each { |s| counts[s[:query]] += 1 }

    counts
      .reject { |q, _| q.strip.length < 2 }
      .sort_by { |_, v| -v }
      .first(50)
      .map { |q, c| { query: q, count: c } }
  end

  # ─── Intent analysis ──────────────────────────────────────────────────────

  def build_intent_analysis
    typed_n = 0; search_n = 0; link_n = 0; other_n = 0
    domain_typed = Hash.new(0)

    categorized.each do |e|
      t = e[:transition].to_i
      case t
      when 1 then typed_n += 1  # TYPED
      when 5, 9, 10 then search_n += 1  # GENERATED / KEYWORD
      when 0 then link_n += 1   # LINK
      else other_n += 1
      end

      tc = e[:typed_count].to_i
      domain_typed[extract_domain(e[:url])] += tc if tc > 0
    end

    total = categorized.size.to_f

    {
      typed_pct:     total > 0 ? ((typed_n  / total) * 100).round(1) : 0,
      search_pct:    total > 0 ? ((search_n / total) * 100).round(1) : 0,
      link_pct:      total > 0 ? ((link_n   / total) * 100).round(1) : 0,
      other_pct:     total > 0 ? ((other_n  / total) * 100).round(1) : 0,
      typed_count:   typed_n,
      link_count:    link_n,
      search_count:  search_n,
      top_intentional: domain_typed
        .select { |_, v| v > 0 }
        .sort_by { |_, v| -v }
        .first(10)
        .map { |d, c| { domain: d, typed_count: c } },
    }
  end

  # ─── Knowledge graph ──────────────────────────────────────────────────────

  def build_knowledge_graph
    top_topics  = build_topics.first(12)
    topic_names = top_topics.map { |t| t[:name] }.to_set

    nodes = top_topics.map do |t|
      { id: t[:name], label: t[:name], size: Math.sqrt(t[:visits]).ceil, visits: t[:visits], color: t[:color] }
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

  # ─── Helpers ──────────────────────────────────────────────────────────────

  def extract_domain(url)
    return "unknown" unless url
    URI.parse(url).host&.downcase&.sub(/^www\./, "") || "unknown"
  rescue URI::InvalidURIError
    "unknown"
  end

  def fmt_hour(h)
    return "12 AM" if h == 0
    return "12 PM" if h == 12
    h < 12 ? "#{h} AM" : "#{h - 12} PM"
  end

  def empty_result
    {
      summary:         { total_visits: 0, unique_domains: 0, has_timestamps: false, has_duration_data: false, total_hours_browsed: 0 },
      topics:          [],
      time_by_topic:   [],
      daily_pattern:   Array.new(24) { |h| { hour: h, visits: 0 } },
      weekly_pattern:  [],
      monthly_trends:  { labels: [], data: [] },
      heatmap:         { grid: Array.new(7) { Array.new(24, 0) }, max: 0, day_labels: %w[Sun Mon Tue Wed Thu Fri Sat] },
      sessions:        { total_sessions: 0, avg_duration_minutes: 0, longest_session_minutes: 0, total_hours_browsed: 0 },
      top_domains:     [],
      top_pages:       [],
      top_searches:    [],
      chrome_searches: [],
      intent:          { typed_pct: 0, search_pct: 0, link_pct: 0, other_pct: 0, top_intentional: [] },
      knowledge_graph: { nodes: [], edges: [] },
    }
  end
end
