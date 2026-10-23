require "sqlite3"

# Builds tiny Firefox, Safari and Chrome history databases (the real table
# names, trimmed to the columns we use) so SQLite imports are tested without
# shipping anyone's real history.
module HistoryDatabases
  # [url, title, visited_at]. The same visits go into every browser's file.
  VISITS = [
    [ "https://github.com/rails/rails", "Rails", Time.utc(2026, 6, 1, 9, 30, 15) ],
    [ "https://github.com/rails/rails", "Rails", Time.utc(2026, 6, 8, 18, 45) ],
    [ "https://news.ycombinator.com/", "Hacker News", Time.utc(2026, 6, 15, 7) ],
    [ "about:preferences", "Settings", Time.utc(2026, 6, 18) ],
    [ "https://developer.mozilla.org/en-US/docs/Web", "MDN", Time.utc(2026, 6, 21, 22, 10, 30.5) ]
  ].freeze

  # What every reader should return: web pages only, one entry per visit, newest first.
  EXPECTED_ENTRIES = VISITS
    .select { |url, _, _| url.start_with?("http") }
    .sort_by { |_, _, time| -time.to_r }
    .map { |url, title, time| { url: url, title: title, visited_at: time, visit_count: 1 } }
    .freeze

  CHROME_EPOCH_OFFSET = 11_644_473_600 # seconds from 1601-01-01 to 1970-01-01

  def self.included(base)
    base.teardown { FileUtils.rm_rf(@history_db_dir) if @history_db_dir }
  end

  # Firefox places.sqlite: visit_date in microseconds since 1970. Firefox keeps
  # it in WAL mode, so the fixture does too.
  def firefox_history_db(name = "places.sqlite")
    build_db(name) do |db|
      db.execute("PRAGMA journal_mode = WAL")
      db.execute_batch(<<~SQL)
        CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0);
        CREATE TABLE moz_historyvisits (id INTEGER PRIMARY KEY, from_visit INTEGER, place_id INTEGER, visit_date INTEGER, visit_type INTEGER);
      SQL
      each_place do |id, url, title, times|
        db.execute("INSERT INTO moz_places (id, url, title, visit_count) VALUES (?, ?, ?, ?)", [ id, url, title, times.size ])
        times.each do |time|
          db.execute("INSERT INTO moz_historyvisits (place_id, visit_date, visit_type) VALUES (?, ?, 1)", [ id, (time.to_r * 1_000_000).to_i ])
        end
      end
    end
  end

  # Safari History.db: visit_time in seconds since 2001-01-01; titles live on visits.
  def safari_history_db(name = "History.db")
    build_db(name) do |db|
      db.execute_batch(<<~SQL)
        CREATE TABLE history_items (id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT NOT NULL UNIQUE, visit_count INTEGER NOT NULL);
        CREATE TABLE history_visits (id INTEGER PRIMARY KEY AUTOINCREMENT, history_item INTEGER NOT NULL, visit_time REAL NOT NULL, title TEXT NULL, load_successful BOOLEAN NOT NULL DEFAULT 1);
      SQL
      each_place do |id, url, title, times|
        db.execute("INSERT INTO history_items (id, url, visit_count) VALUES (?, ?, ?)", [ id, url, times.size ])
        times.each do |time|
          db.execute("INSERT INTO history_visits (history_item, visit_time, title) VALUES (?, ?, ?)", [ id, (time.to_r - 978_307_200).to_f, title ])
        end
      end
    end
  end

  # Chrome History: visit_time in microseconds since 1601-01-01.
  def chrome_history_db(name = "History")
    build_db(name) do |db|
      db.execute_batch(<<~SQL)
        CREATE TABLE urls (id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0 NOT NULL, typed_count INTEGER DEFAULT 0 NOT NULL, last_visit_time INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE visits (id INTEGER PRIMARY KEY, url INTEGER NOT NULL, visit_time INTEGER NOT NULL, from_visit INTEGER, transition INTEGER DEFAULT 0 NOT NULL, visit_duration INTEGER DEFAULT 0 NOT NULL);
      SQL
      each_place do |id, url, title, times|
        db.execute("INSERT INTO urls (id, url, title, visit_count) VALUES (?, ?, ?, ?)", [ id, url, title, times.size ])
        times.each do |time|
          db.execute("INSERT INTO visits (url, visit_time) VALUES (?, ?)", [ id, ((time.to_r + CHROME_EPOCH_OFFSET) * 1_000_000).to_i ])
        end
      end
    end
  end

  # A valid SQLite database that is not browser history.
  def unknown_sqlite_db(name = "notes.sqlite")
    build_db(name) { |db| db.execute("CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT)") }
  end

  # The SQLite magic header followed by junk, like a truncated or damaged copy.
  def corrupt_sqlite_db(name = "places.sqlite")
    path = File.join(history_db_dir, name)
    File.binwrite(path, SqliteHistoryReader::HEADER + ("\xFF\x00junk".b * 300))
    path
  end

  private

  def history_db_dir
    @history_db_dir ||= Dir.mktmpdir("history_dbs")
  end

  def build_db(name)
    path = File.join(history_db_dir, name)
    FileUtils.rm_f(path) # always build from scratch
    db = SQLite3::Database.new(path)
    yield db
    path
  ensure
    db&.close
  end

  def each_place
    VISITS.group_by(&:first).each_with_index do |(url, visits), index|
      yield index + 1, url, visits.first[1], visits.map(&:last)
    end
  end
end
