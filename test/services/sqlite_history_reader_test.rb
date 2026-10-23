require "test_helper"

class SqliteHistoryReaderTest < ActiveSupport::TestCase
  include HistoryDatabases

  def normalised(entries)
    entries.map { |e| e.slice(:url, :title, :visited_at, :visit_count) }
  end

  test "recognises each browser by its tables, not its file name" do
    assert_equal :firefox, SqliteHistoryReader.detect(firefox_history_db("upload.bin"))
    assert_equal :safari,  SqliteHistoryReader.detect(safari_history_db("History"))
    assert_equal :chrome,  SqliteHistoryReader.detect(chrome_history_db("History.db"))
  end

  test "reads Firefox visits with microsecond Unix timestamps" do
    assert_equal EXPECTED_ENTRIES, SqliteHistoryReader.read(firefox_history_db)
  end

  test "reads Safari visits with seconds since 2001-01-01" do
    entries = SqliteHistoryReader.read(safari_history_db)

    assert_equal EXPECTED_ENTRIES, entries
    assert_equal Time.utc(2026, 6, 21, 22, 10, 30.5), entries.first[:visited_at]
  end

  test "reads Chrome visits with microseconds since 1601 and keeps Chrome's extra fields" do
    entries = SqliteHistoryReader.read(chrome_history_db)

    assert_equal EXPECTED_ENTRIES, normalised(entries)
    assert entries.first.key?(:effective_duration)
  end

  test "times are UTC whatever the server time zone" do
    entries = SqliteHistoryReader.read(firefox_history_db)

    assert entries.all? { |e| e[:visited_at].utc? }
    assert_equal "2026-06-01T09:30:15Z", entries.last[:visited_at].iso8601
  end

  # sqlite3 2.9 interrupted any query longer than ~1000 VM steps when
  # statement_timeout was set, so only tiny fixtures could be read.
  test "reads a realistically sized history from every browser within the time limit" do
    visits = many_visits

    %i[firefox safari chrome].each do |browser|
      entries = SqliteHistoryReader.read(send("#{browser}_history_db", "#{browser}-big", visits: visits))

      assert_equal 3_000, entries.size, browser
      assert_equal visits.last.last, entries.first[:visited_at], browser
    end
  end

  test "an unknown SQLite database is detected as nil and refused when read" do
    path = unknown_sqlite_db

    assert_nil SqliteHistoryReader.detect(path)
    error = assert_raises(SqliteHistoryReader::UnknownDatabaseError) { SqliteHistoryReader.read(path) }
    assert_match(/places\.sqlite/, error.message)
  end

  test "views named like history tables do not count" do
    path = build_db("views.sqlite") do |db|
      db.execute_batch(<<~SQL)
        CREATE TABLE data (x);
        CREATE VIEW moz_places AS SELECT x AS url FROM data;
        CREATE VIEW moz_historyvisits AS SELECT x AS visit_date FROM data;
      SQL
    end

    assert_nil SqliteHistoryReader.detect(path)
  end

  test "a damaged database raises CorruptDatabaseError" do
    error = assert_raises(SqliteHistoryReader::CorruptDatabaseError) { SqliteHistoryReader.detect(corrupt_sqlite_db) }
    assert_match(/damaged/, error.message)
    assert_kind_of HistoryParser::UnsupportedFormatError, error
  end

  test "never changes the upload and deletes its temp copy" do
    path   = firefox_history_db
    digest = Digest::SHA256.file(path).hexdigest
    tmp    = Dir.mktmpdir

    with_tmpdir(tmp) { SqliteHistoryReader.read(path) }

    assert_equal digest, Digest::SHA256.file(path).hexdigest
    assert_empty Dir.children(tmp)
  ensure
    FileUtils.rm_rf(tmp)
  end

  test "HistoryParser.parse_file reads SQLite databases and text exports" do
    assert_equal EXPECTED_ENTRIES, HistoryParser.parse_file(safari_history_db)

    csv = File.join(Dir.mktmpdir, "history.csv")
    File.write(csv, "url,title\nhttps://github.com,GitHub\n")
    assert_equal "https://github.com", HistoryParser.parse_file(csv).first[:url]
  ensure
    FileUtils.rm_rf(File.dirname(csv)) if csv
  end

  private

  def with_tmpdir(dir)
    original = ENV["TMPDIR"]
    ENV["TMPDIR"] = dir
    yield
  ensure
    ENV["TMPDIR"] = original
  end
end
