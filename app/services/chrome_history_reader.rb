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

  def self.available?
    history_paths.any?
  end

  def self.read
    paths = history_paths
    raise "Chrome/Chromium history not found. Make sure Chrome has been used at least once." if paths.empty?

    all_entries = paths.flat_map { |p| read_file(p) }
    raise "No history entries found in Chrome." if all_entries.empty?

    # De-duplicate across profiles and sort newest first
    all_entries
      .uniq { |e| [e[:url], e[:visited_at]&.to_i] }
      .sort_by { |e| -(e[:visited_at]&.to_i || 0) }
      .first(MAX_VISITS)
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
    entries = query_entries(tmp)
    entries
  rescue => e
    Rails.logger.warn("ChromeHistoryReader: skipping #{path} — #{e.message}")
    []
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

  # Use array indexing — avoids results_as_hash key-type differences across sqlite3 versions.
  # Column order: 0=url, 1=title, 2=visit_time
  def self.query_entries(db_path)
    db = SQLite3::Database.new(db_path, { readonly: true })
    db.busy_timeout = 2000

    db.execute(<<~SQL).filter_map { |row| parse_row(row) }
      SELECT u.url, u.title, v.visit_time
      FROM visits v
      INNER JOIN urls u ON u.id = v.url
      WHERE u.url LIKE 'http%'
      ORDER BY v.visit_time DESC
      LIMIT #{MAX_VISITS}
    SQL
  ensure
    db&.close
  end

  def self.parse_row(row)
    url = row[0]
    return nil unless url.is_a?(String) && url.start_with?("http")
    { url: url, title: row[1].to_s, visited_at: chrome_time(row[2]), visit_count: 1 }
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
