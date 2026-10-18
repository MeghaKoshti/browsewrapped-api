require "test_helper"

class AnalysesTest < ActionDispatch::IntegrationTest
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
    assert_equal "No file provided", response.parsed_body["error"]
  end

  test "POST /api/v1/analyze with an unsupported file returns 422" do
    file = Rack::Test::UploadedFile.new(StringIO.new("just some text"), "text/plain", original_filename: "notes.txt")

    post "/api/v1/analyze", params: { file: file }

    assert_response :unprocessable_entity
    assert_match(/Unsupported format/, response.parsed_body["error"])
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
