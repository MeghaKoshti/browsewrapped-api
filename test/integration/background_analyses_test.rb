require "test_helper"

class BackgroundAnalysesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def sample_upload
    Rack::Test::UploadedFile.new(Rails.root.join("sample/sample_history.json"), "application/json")
  end

  def with_sync_threshold(bytes)
    original = ENV["ANALYSIS_SYNC_THRESHOLD_BYTES"]
    ENV["ANALYSIS_SYNC_THRESHOLD_BYTES"] = bytes.to_s
    yield
  ensure
    ENV["ANALYSIS_SYNC_THRESHOLD_BYTES"] = original
  end

  test "POST /api/v1/analyses enqueues a job for large files and returns 202" do
    with_sync_threshold(0) do
      assert_enqueued_with(job: AnalyzeHistoryJob) do
        post "/api/v1/analyses", params: { file: sample_upload }
      end
    end

    assert_response :accepted
    body = response.parsed_body
    assert_equal "pending", body["status"]
    assert body["id"].present?
    assert_not body.key?("result")
  end

  test "polling GET /api/v1/analyses/:id returns the result once the job has run" do
    with_sync_threshold(0) { post "/api/v1/analyses", params: { file: sample_upload } }
    id = response.parsed_body["id"]

    get "/api/v1/analyses/#{id}"
    assert_response :success
    assert_equal "pending", response.parsed_body["status"]

    perform_enqueued_jobs

    get "/api/v1/analyses/#{id}"
    assert_response :success
    body = response.parsed_body
    assert_equal "completed", body["status"]
    assert_operator body.dig("result", "summary", "total_visits"), :>, 0
    assert_equal id, body.dig("result", "meta", "analysis_id")
  end

  test "small files are analysed synchronously and return 201 with the result" do
    with_sync_threshold(5.megabytes) do
      assert_no_enqueued_jobs do
        post "/api/v1/analyses", params: { file: sample_upload }
      end
    end

    assert_response :created
    body = response.parsed_body
    assert_equal "completed", body["status"]
    assert body["result"].key?("persona")
  end

  test "a failed analysis reports its error message" do
    file = Rack::Test::UploadedFile.new(StringIO.new("just some text"), "text/plain", original_filename: "notes.txt")
    post "/api/v1/analyses", params: { file: file }

    assert_response :created
    get "/api/v1/analyses/#{response.parsed_body["id"]}"
    body = response.parsed_body
    assert_equal "failed", body["status"]
    assert_match(/Unsupported format/, body["error_message"])
  end

  test "POST /api/v1/analyses without a file returns 422" do
    post "/api/v1/analyses"

    assert_response :unprocessable_entity
    assert_equal "No file provided", response.parsed_body["error"]
  end

  test "GET /api/v1/analyses/:id for an unknown id returns 404" do
    get "/api/v1/analyses/#{SecureRandom.uuid}"

    assert_response :not_found
  end
end
