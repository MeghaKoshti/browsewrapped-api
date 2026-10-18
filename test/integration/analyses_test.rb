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
end
