require "test_helper"

class SharedReportsTest < ActionDispatch::IntegrationTest
  def sample_report
    @sample_report ||= begin
      entries = HistoryParser.parse(File.read(Rails.root.join("sample/sample_history.json")))
      HistoryAnalyzer.new(entries).analyze.merge(meta: { source: "sample" }).as_json
    end
  end

  def share!(payload = { report: sample_report })
    post "/api/v1/shared_reports", params: payload, as: :json
    response.parsed_body
  end

  test "creating a share link returns the token, path and a one-time delete token" do
    body = share!

    assert_response :created
    assert_equal "/r/#{body["token"]}", body["path"]
    assert body["delete_token"].present?
    assert body["expires_at"].present?
  end

  test "a completed analysis can be shared by id" do
    analysis = Analysis.create!(status: :completed, result: sample_report)

    body = share!(analysis_id: analysis.id)

    assert_response :created
    get "/api/v1/shared_reports/#{body["token"]}"
    assert_equal sample_report.dig("summary", "total_visits"), response.parsed_body.dig("report", "summary", "total_visits")
  end

  test "the public link shows the sanitised report without the delete token" do
    token = share!["token"]

    get "/api/v1/shared_reports/#{token}"

    assert_response :success
    body = response.parsed_body
    assert body["report"].key?("persona")
    assert_equal 30, body.dig("report", "period_comparison", "window_days")
    assert_not body["report"].key?("top_pages")
    assert_not body["report"].key?("top_searches")
    assert_not body.key?("delete_token")
    assert_not body.to_json.include?("delete_token_digest")
  end

  test "the owner can delete a share link with the delete token" do
    body = share!

    delete "/api/v1/shared_reports/#{body["token"]}", headers: { "X-Delete-Token" => body["delete_token"] }
    assert_response :no_content

    get "/api/v1/shared_reports/#{body["token"]}"
    assert_response :not_found
  end

  test "deleting with a wrong token is forbidden" do
    body = share!

    delete "/api/v1/shared_reports/#{body["token"]}", headers: { "X-Delete-Token" => "nope" }

    assert_response :forbidden
    assert SharedReport.exists?(token: body["token"])
  end

  test "unknown tokens return 404" do
    get "/api/v1/shared_reports/doesnotexist"

    assert_response :not_found
  end

  test "expired links return 404" do
    token = share!["token"]

    travel 31.days do
      get "/api/v1/shared_reports/#{token}"
      assert_response :not_found
    end
  end

  test "sharing nothing returns 422" do
    share!({})

    assert_response :unprocessable_entity
  end

  test "sharing an analysis that is not completed returns 422" do
    share!(analysis_id: Analysis.create!.id)

    assert_response :unprocessable_entity
  end
end
