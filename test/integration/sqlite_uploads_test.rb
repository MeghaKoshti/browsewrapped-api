require "test_helper"

class SqliteUploadsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include HistoryDatabases

  def upload(path)
    Rack::Test::UploadedFile.new(path, "application/octet-stream", original_filename: File.basename(path))
  end

  def with_env(key, value)
    original = ENV[key]
    ENV[key] = value.to_s
    yield
  ensure
    ENV[key] = original
  end

  test "POST /api/v1/analyze reads a Firefox places.sqlite" do
    post "/api/v1/analyze", params: { file: upload(firefox_history_db) }

    assert_response :success
    body = response.parsed_body
    assert_equal 4, body.dig("summary", "total_visits")
    assert_includes body["top_domains"].map { |d| d["domain"] }, "github.com"
    assert_equal 10, body.dig("period_comparison", "window_days"), "20 days of history compare 10 with 10"
  end

  test "POST /api/v1/analyses analyses a small Safari History.db straight away" do
    with_env("ANALYSIS_SYNC_THRESHOLD_BYTES", 5.megabytes) do
      post "/api/v1/analyses", params: { file: upload(safari_history_db) }
    end

    assert_response :created
    body = response.parsed_body
    assert_equal "completed", body["status"]
    assert_equal "History.db", body["filename"]
    assert_equal 4, body.dig("result", "meta", "total_entries_parsed")
  end

  test "POST /api/v1/analyses reads a Chrome History file in the background job" do
    with_env("ANALYSIS_SYNC_THRESHOLD_BYTES", 0) do
      post "/api/v1/analyses", params: { file: upload(chrome_history_db) }
    end
    assert_response :accepted
    id = response.parsed_body["id"]

    perform_enqueued_jobs

    get "/api/v1/analyses/#{id}"
    body = response.parsed_body
    assert_equal "completed", body["status"]
    assert_equal 4, body.dig("result", "summary", "total_visits")
    assert_not AnalysisUpload.exist?(id)
  end

  test "an unknown SQLite database gets 415 unsupported_sqlite and nothing is stored" do
    %w[/api/v1/analyze /api/v1/analyses].each do |path|
      assert_no_difference("Analysis.count") { post path, params: { file: upload(unknown_sqlite_db) } }

      assert_response :unsupported_media_type
      assert_equal "unsupported_sqlite", response.parsed_body.dig("error", "code")
      assert_match(/Firefox's places\.sqlite, Safari's History\.db or Chrome's History/, response.parsed_body.dig("error", "message"))
    end
  end

  test "a damaged SQLite file gets 422 corrupt_sqlite" do
    assert_no_difference("Analysis.count") { post "/api/v1/analyses", params: { file: upload(corrupt_sqlite_db) } }

    assert_response :unprocessable_entity
    assert_equal "corrupt_sqlite", response.parsed_body.dig("error", "code")
  end

  test "the upload size limit applies to databases too" do
    with_env("ANALYSIS_MAX_UPLOAD_BYTES", 1024) do
      post "/api/v1/analyze", params: { file: upload(firefox_history_db) }
    end

    assert_response :content_too_large
    assert_equal "payload_too_large", response.parsed_body.dig("error", "code")
  end
end
