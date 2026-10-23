require "test_helper"

class UploadSnifferTest < ActiveSupport::TestCase
  def detect(content)
    file = Tempfile.new("upload")
    file.binmode
    file.write(content)
    file.close
    UploadSniffer.detect(file.path)
  ensure
    file&.unlink
  end

  test "recognises JSON objects and arrays, with or without a BOM or leading whitespace" do
    assert_equal :json, detect('{"Browser History": []}')
    assert_equal :json, detect("\n  [{\"url\": \"https://github.com\"}]")
    assert_equal :json, detect("\xEF\xBB\xBF[]".b)
  end

  test "recognises CSV by a comma in the header line" do
    assert_equal :csv, detect("url,title,visit_time\nhttps://github.com,GitHub,2026-06-01\n")
  end

  test "reports empty and whitespace-only files as empty" do
    assert_equal :empty, detect("")
    assert_equal :empty, detect("  \n\t")
  end

  test "rejects binary files and plain text" do
    assert_nil detect("\x89PNG\r\n\x1A\n\x00\x00".b)
    assert_nil detect("PK\x03\x04\x14\x00".b)
    assert_nil detect("SQLite format 3\x00".b)
    assert_nil detect("%PDF-1.7\n%\xE2\xE3\xCF\xD3".b)
    assert_nil detect("just some notes")
  end
end
