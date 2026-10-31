require "test_helper"

class AnalysesTest < ActionDispatch::IntegrationTest
  def upload_of(content, filename, type = "application/octet-stream")
    Rack::Test::UploadedFile.new(StringIO.new(content), type, original_filename: filename)
  end

  def with_env(key, value)
    original = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = original
  end

  test "POST /api/v1/analyze returns a report for the sample file" do
    file = Rack::Test::UploadedFile.new(Rails.root.join("sample/sample_history.json"), "application/json")

    post "/api/v1/analyze", params: { file: file }

    assert_response :success
    body = response.parsed_body
    assert_equal "upload", body.dig("meta", "source")
    assert_operator body.dig("summary", "total_visits"), :>, 0
    assert body.key?("persona")
  end

  test "POST /api/v1/analyze without a file returns 422" do
    post "/api/v1/analyze"

    assert_response :unprocessable_entity
    assert_equal({ "code" => "missing_file", "message" => "No file provided" }, response.parsed_body["error"])
    assert_equal "No file provided", response.parsed_body["error_message"]
  end

  test "POST /api/v1/analyze with plain text returns 415" do
    post "/api/v1/analyze", params: { file: upload_of("just some text", "notes.txt") }

    assert_response :unsupported_media_type
    assert_equal "unsupported_media_type", response.parsed_body.dig("error", "code")
  end

  test "POST /api/v1/analyze sniffs the content, not the extension" do
    png = "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR".b

    post "/api/v1/analyze", params: { file: upload_of(png, "history.json", "application/json") }

    assert_response :unsupported_media_type
  end

  test "POST /api/v1/analyze accepts a CSV export whatever its extension" do
    csv = "url,title\nhttps://github.com,GitHub\n"

    post "/api/v1/analyze", params: { file: upload_of(csv, "export.txt", "text/plain") }

    assert_response :success
    assert_equal 1, response.parsed_body.dig("summary", "total_visits")
  end

  test "POST /api/v1/analyze with an empty file returns 422" do
    post "/api/v1/analyze", params: { file: upload_of("", "history.json") }

    assert_response :unprocessable_entity
    assert_equal({ "code" => "empty_file", "message" => "The file is empty" }, response.parsed_body["error"])
  end

  test "POST /api/v1/analyze with CSV the parser can't read returns 422 unsupported_format" do
    post "/api/v1/analyze", params: { file: upload_of("name,age\nbob,3\n", "people.csv") }

    assert_response :unprocessable_entity
    assert_equal "unsupported_format", response.parsed_body.dig("error", "code")
    assert_match(/Unsupported format/, response.parsed_body.dig("error", "message"))
  end

  test "POST /api/v1/analyze with a file over the size limit returns 413" do
    with_env("ANALYSIS_MAX_UPLOAD_BYTES", "10") do
      post "/api/v1/analyze", params: { file: upload_of("url\nhttps://github.com\n", "big.csv") }
    end

    assert_response :content_too_large
    assert_equal({ "code" => "payload_too_large", "message" => "File too large (max 10 Bytes)" }, response.parsed_body["error"])
  end

  test "uploads are rate limited per IP across /analyze and /analyses" do
    ApplicationController::UPLOAD_RATE_LIMIT.times { post "/api/v1/analyses" }
    assert_response :unprocessable_entity

    post "/api/v1/analyze"

    assert_response :too_many_requests
    assert_equal "rate_limited", response.parsed_body.dig("error", "code")
    assert_equal "60", response.headers["Retry-After"]

    post "/api/v1/analyze", env: { "REMOTE_ADDR" => "203.0.113.9" }
    assert_response :unprocessable_entity, "another IP has its own limit"
  end

  test "polling an analysis is not rate limited" do
    (ApplicationController::UPLOAD_RATE_LIMIT + 1).times { get "/api/v1/analyses/#{SecureRandom.uuid}" }

    assert_response :not_found
  end

  test "GET /api/v1/sample returns the sample report" do
    get "/api/v1/sample"

    assert_response :success
    body = response.parsed_body
    assert_equal "sample", body.dig("meta", "source")
    assert_operator body.dig("meta", "total_entries_parsed"), :>, 0
    %w[summary persona topics top_domains daily_pattern knowledge_graph].each do |key|
      assert body.key?(key), "expected #{key} in the sample report"
    end
    assert_equal 30, body.dig("period_comparison", "window_days")
    assert_operator body.dig("period_comparison", "topics").size, :>, 0
  end

  test "GET /api/v1/sample is served from the cache on repeat calls" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    get "/api/v1/sample"
    first = response.parsed_body
    assert Rails.cache.exist?(Api::V1::AnalysesController::SAMPLE_CACHE_KEY)

    travel 1.minute do
      get "/api/v1/sample"
    end

    assert_response :success
    assert_equal first.dig("meta", "processed_at"), response.parsed_body.dig("meta", "processed_at")
  ensure
    Rails.cache = original_cache
  end
end
