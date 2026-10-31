require "sqlite3"
require "fileutils"
require "tmpdir"

# Reads an uploaded browser history database: Firefox's places.sqlite,
# Safari's History.db or Chrome's History file. The browser is recognised by
# its tables, never by the file name.
#
# Uploads are untrusted, so the file is copied into a private temp dir (deleted
# afterwards) and opened read-only and immutable: SQLite takes no locks and
# writes no journal or WAL files. Extensions stay disabled, functions in the
# file's schema are not trusted, and every query has a time limit.
class SqliteHistoryReader
  # Subclasses of the parser's error, so callers that already show
  # UnsupportedFormatError messages to users handle these too.
  class UnknownDatabaseError < HistoryParser::UnsupportedFormatError; end
  class CorruptDatabaseError < HistoryParser::UnsupportedFormatError; end

  HEADER = "SQLite format 3\0".b

  # The tables (not views) that identify each browser's history file.
  BROWSER_TABLES = {
    firefox: %w[moz_places moz_historyvisits],
    safari:  %w[history_items history_visits],
    chrome:  %w[urls visits]
  }.freeze

  MAX_VISITS       = ChromeHistoryReader::MAX_VISITS
  QUERY_TIMEOUT_MS = 10_000
  SAFARI_EPOCH     = 978_307_200 # 2001-01-01 00:00:00 UTC, in Unix seconds

  UNKNOWN_MESSAGE = "This SQLite file is not a browser history database we can read. " \
                    "Upload Firefox's places.sqlite, Safari's History.db or Chrome's History file.".freeze
  CORRUPT_MESSAGE = "This history database looks damaged or incomplete. " \
                    "Close the browser, copy the file again and retry.".freeze

  def self.sqlite?(path)
    File.binread(path, HEADER.bytesize) == HEADER
  end

  # :firefox, :safari, :chrome, or nil for any other SQLite database.
  def self.detect(path)
    with_database(path) { |db| browser_for(db) }
  end

  # Normalised entries (url, title, visited_at, visit_count), one per visit,
  # newest first, like HistoryParser returns.
  def self.read(path)
    with_database(path) do |db|
      case browser_for(db)
      when :firefox then firefox_entries(db)
      when :safari  then safari_entries(db)
      when :chrome  then ChromeHistoryReader.query_entries(db)
      else raise UnknownDatabaseError, UNKNOWN_MESSAGE
      end
    end
  end

  def self.with_database(path)
    Dir.mktmpdir("bw_sqlite") do |dir|
      copy = File.join(dir, "history.db")
      FileUtils.cp(path, copy)

      db = SQLite3::Database.new("file:#{uri_escape(copy)}?immutable=1",
                                 flags: SQLite3::Constants::Open::READONLY | SQLite3::Constants::Open::URI)
      db.execute("PRAGMA trusted_schema = OFF")
      db.statement_timeout = QUERY_TIMEOUT_MS
      yield db
    ensure
      db&.close
    end
  rescue SQLite3::NotADatabaseException, SQLite3::CorruptException
    raise CorruptDatabaseError, CORRUPT_MESSAGE
  rescue SQLite3::SQLException
    # The right tables but not the columns we expect (e.g. a very old version).
    raise UnknownDatabaseError, UNKNOWN_MESSAGE
  end

  def self.browser_for(db)
    tables = db.execute("SELECT name FROM sqlite_master WHERE type = 'table'").flatten
    BROWSER_TABLES.find { |_, required| (required - tables).empty? }&.first
  end

  # Firefox: visit_date is microseconds since the Unix epoch.
  def self.firefox_entries(db)
    rows = db.execute(<<~SQL, [ MAX_VISITS ])
      SELECT p.url, p.title, v.visit_date
      FROM moz_historyvisits v
      JOIN moz_places p ON p.id = v.place_id
      WHERE p.url LIKE 'http%'
      ORDER BY v.visit_date DESC
      LIMIT ?
    SQL
    rows.map { |url, title, usec| entry(url, title, usec && plausible(Time.at(0, usec.to_i, :usec))) }
  end

  # Safari: visit_time is seconds (with a fraction) since 2001-01-01 UTC.
  def self.safari_entries(db)
    rows = db.execute(<<~SQL, [ MAX_VISITS ])
      SELECT i.url, v.title, v.visit_time
      FROM history_visits v
      JOIN history_items i ON i.id = v.history_item
      WHERE i.url LIKE 'http%'
      ORDER BY v.visit_time DESC
      LIMIT ?
    SQL
    rows.map { |url, title, seconds| entry(url, title, seconds && plausible(Time.at(SAFARI_EPOCH + seconds.to_r.round(6)))) }
  end

  def self.entry(url, title, visited_at)
    { url: url, title: title.to_s, visited_at: visited_at, visit_count: 1 }
  end

  # Same sanity window as the Chrome reader: anything else is a bad clock or a bad file.
  def self.plausible(time)
    time = time.utc
    time.year.between?(2000, 2040) ? time : nil
  end

  # The temp path is ours, but %, ? and # would still break a SQLite URI.
  def self.uri_escape(path)
    path.gsub(/[%?#]/) { |char| format("%%%02X", char.ord) }
  end

  private_class_method :with_database, :browser_for, :firefox_entries, :safari_entries,
                       :entry, :plausible, :uri_escape
end
