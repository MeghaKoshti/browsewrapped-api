require "sqlite3"
require "fileutils"
require "tmpdir"
require "securerandom"

class ChromeHistoryReader
  PROFILE_DIRS = ["Default", "Profile 1", "Profile 2", "Profile 3"].freeze

  SEARCH_ROOTS = [
    File.expand_path("~/.config/google-chrome"),
    File.expand_path("~/.config/chromium"),
    File.expand_path("~/.config/google-chrome-beta"),
    File.expand_path("~/Library/Application Support/Google/Chrome"),
    File.expand_path("~/Library/Application Support/Chromium"),
  ].freeze

  MAX_VISITS = 200_000

  # Core page transition types (lower 8 bits of transition column)
  TRANSITION_LINK      = 0
  TRANSITION_TYPED     = 1
  TRANSITION_GENERATED = 5
  TRANSITION_FORM      = 7
  TRANSITION_RELOAD    = 8
  TRANSITION_KEYWORD   = 9
  TRANSITION_KEYWORD_G = 10

  def self.available?
    history_paths.any?
  end

  # Returns { entries: [...], searches: [...] }
  def self.read
    paths = history_paths
    raise "Chrome/Chromium history not found. Make sure Chrome has been used at least once." if paths.empty?

    all_entries = []
    all_searches = []

    paths.each do |path|
      data = read_file(path)
      all_entries.concat(data[:entries])
      all_searches.concat(data[:searches])
    end

    raise "No history entries found in Chrome." if all_entries.empty?

    entries = all_entries
      .uniq { |e| [e[:url], e[:visited_at]&.to_i] }
      .sort_by { |e| -(e[:visited_at]&.to_i || 0) }
      .first(MAX_VISITS)

    searches = all_searches
      .uniq { |s| [s[:query], s[:visited_at]&.to_i] }
      .sort_by { |s| -(s[:visited_at]&.to_i || 0) }

    { entries: entries, searches: searches }
  end

  def self.history_paths
    SEARCH_ROOTS.flat_map do |root|
      next [] unless Dir.exist?(root)
      PROFILE_DIRS.map { |p| File.join(root, p, "History") }
    end.select { |f| File.exist?(f) }
  end

  private

  def self.read_file(path)
    tmp = File.join(Dir.tmpdir, "bwrapped_#{SecureRandom.hex(6)}.db")
    copy_db(path, tmp)
    entries  = query_entries(tmp)
    searches = query_keyword_searches(tmp)
    { entries: entries, searches: searches }
  rescue => e
    Rails.logger.warn("ChromeHistoryReader: skipping #{path} — #{e.message}")
    { entries: [], searches: [] }
  ensure
    cleanup(tmp)
  end

  def self.copy_db(source, dest)
    FileUtils.cp(source, dest)
    FileUtils.cp("#{source}-wal", "#{dest}-wal") if File.exist?("#{source}-wal")
    FileUtils.cp("#{source}-shm", "#{dest}-shm") if File.exist?("#{source}-shm")
  rescue Errno::EACCES => e
    raise "Cannot read Chrome history file (permission denied): #{e.message}"
  end

  # Column order: 0=url, 1=title, 2=typed_count, 3=visit_time, 4=visit_duration, 5=transition
  def self.query_entries(db_path)
    db = SQLite3::Database.new(db_path, { readonly: true })
    db.busy_timeout = 2000

    db.execute(<<~SQL).filter_map { |row| parse_row(row) }
      SELECT u.url, u.title, u.typed_count,
             v.visit_time, v.visit_duration, v.transition
      FROM visits v
      INNER JOIN urls u ON u.id = v.url
      WHERE u.url LIKE 'http%'
      ORDER BY v.visit_time DESC
      LIMIT #{MAX_VISITS}
    SQL
  ensure
    db&.close
  end

  def self.query_keyword_searches(db_path)
    db = SQLite3::Database.new(db_path, { readonly: true })
    db.busy_timeout = 2000

    has_table = db.execute(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='keyword_search_terms'"
    ).flatten.any?
    return [] unless has_table

    db.execute(<<~SQL).filter_map do |row|
      SELECT k.term, v.visit_time
      FROM keyword_search_terms k
      JOIN urls u ON u.id = k.url_id
      JOIN visits v ON v.url = u.id
      WHERE k.term IS NOT NULL AND length(trim(k.term)) >= 2
      ORDER BY v.visit_time DESC
      LIMIT 20000
    SQL
      term = row[0].to_s.strip
      next if term.length < 2
      { query: term, visited_at: chrome_time(row[1]) }
    end
  rescue => e
    Rails.logger.warn("ChromeHistoryReader: keyword_search_terms error — #{e.message}")
    []
  ensure
    db&.close
  end

  def self.parse_row(row)
    url = row[0]
    return nil unless url.is_a?(String) && url.start_with?("http")
    {
      url: url,
      title: row[1].to_s,
      typed_count: row[2].to_i,
      visited_at: chrome_time(row[3]),
      visit_duration: row[4].to_i,   # microseconds; 0 means unknown
      transition: row[5].to_i & 0xFF, # strip qualifier bits, keep core type
      visit_count: 1,
    }
  end

  # Chrome stores times as microseconds since Jan 1, 1601 (Windows FILETIME)
  def self.chrome_time(usec)
    return nil unless usec
    t = Time.at(usec.to_i / 1_000_000.0 - 11_644_473_600).utc
    t.year.between?(2000, 2040) ? t : nil
  rescue
    nil
  end

  def self.cleanup(path)
    FileUtils.rm_f(path)
    FileUtils.rm_f("#{path}-wal")
    FileUtils.rm_f("#{path}-shm")
  end
end
