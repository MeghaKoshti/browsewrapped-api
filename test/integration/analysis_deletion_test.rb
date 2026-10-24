require "test_helper"

class AnalysisDeletionTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def sample_upload
    Rack::Test::UploadedFile.new(Rails.root.join("sample/sample_history.json"), "application/json")
  end

  def upload!
    post "/api/v1/analyses", params: { file: sample_upload }
    response.parsed_body
  end

  test "creating an analysis returns a one-time delete token and stores only its digest" do
    body = upload!

    assert_response :created
    assert_operator body["delete_token"].length, :>=, 32
    analysis = Analysis.find(body["id"])
    assert_equal Analysis.digest(body["delete_token"]), analysis.delete_token_digest
    assert_not_includes analysis.attributes.values.map(&:to_s), body["delete_token"]

    get "/api/v1/analyses/#{body["id"]}"
    assert_not response.parsed_body.key?("delete_token")
  end

  test "the owner can delete an analysis with the delete token" do
    body = upload!

    delete "/api/v1/analyses/#{body["id"]}", headers: { "X-Delete-Token" => body["delete_token"] }

    assert_response :no_content
    assert_not Analysis.exists?(body["id"])
    get "/api/v1/analyses/#{body["id"]}"
    assert_response :not_found
  end

  test "deleting a queued analysis also removes the waiting upload" do
    original = ENV["ANALYSIS_SYNC_THRESHOLD_BYTES"]
    ENV["ANALYSIS_SYNC_THRESHOLD_BYTES"] = "0"
    body = upload!
    assert_response :accepted
    assert body["delete_token"].present?
    assert AnalysisUpload.exist?(body["id"])

    delete "/api/v1/analyses/#{body["id"]}", headers: { "X-Delete-Token" => body["delete_token"] }

    assert_response :no_content
    assert_not AnalysisUpload.exist?(body["id"])
    perform_enqueued_jobs # the job finds nothing and does nothing
    assert_not Analysis.exists?(body["id"])
  ensure
    ENV["ANALYSIS_SYNC_THRESHOLD_BYTES"] = original
  end

  test "a wrong or missing delete token is forbidden" do
    body = upload!

    delete "/api/v1/analyses/#{body["id"]}", headers: { "X-Delete-Token" => "nope" }
    assert_response :forbidden
    assert_equal "invalid_delete_token", response.parsed_body.dig("error", "code")

    delete "/api/v1/analyses/#{body["id"]}"
    assert_response :forbidden
    assert Analysis.exists?(body["id"])
  end

  test "analyses without a stored digest can't be deleted by token" do
    analysis = Analysis.create!(status: :completed, result: {})

    delete "/api/v1/analyses/#{analysis.id}", headers: { "X-Delete-Token" => "" }

    assert_response :forbidden
  end

  test "unknown analyses return 404" do
    delete "/api/v1/analyses/#{SecureRandom.uuid}", headers: { "X-Delete-Token" => "x" * 32 }
    assert_response :not_found

    delete "/api/v1/analyses/not-a-uuid", headers: { "X-Delete-Token" => "x" * 32 }
    assert_response :not_found
  end
end
