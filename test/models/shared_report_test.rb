require "test_helper"

class SharedReportTest < ActiveSupport::TestCase
  def report
    { "summary" => { "total_visits" => 10, "top_domain" => "example.com" }, "top_pages" => [ { "url" => "https://example.com/x" } ] }
  end

  test "generates an unguessable token and a delete token, storing only the digest" do
    shared = SharedReport.build_from_report(report)
    shared.save!

    assert_operator shared.token.length, :>=, 10
    assert_not_equal shared.id.to_s, shared.token
    assert_operator shared.delete_token.length, :>=, 20
    assert_not_equal shared.delete_token, shared.delete_token_digest
    assert shared.deletable_with?(shared.delete_token)
    assert_not shared.deletable_with?("wrong")
    assert_not shared.deletable_with?(nil)
  end

  test "sanitises the report before saving" do
    shared = SharedReport.build_from_report(report)
    shared.save!

    assert_not shared.data.key?("top_pages")
    assert_not shared.data["summary"].key?("top_domain")
  end

  test "expires after 30 days" do
    shared = SharedReport.build_from_report(report)
    shared.save!

    assert_in_delta 30.days.from_now, shared.expires_at, 5.seconds
    assert_not shared.expired?
    travel 31.days do
      assert shared.expired?
      assert_not SharedReport.active.exists?(shared.id)
    end
  end

  test "requires a report with a summary" do
    assert_not SharedReport.build_from_report({ "persona" => {} }).valid?
  end

  test "rejects reports that are too large" do
    huge = report.merge("persona" => { "description" => "x" * (SharedReport::MAX_DATA_BYTES + 1) })

    assert_not SharedReport.build_from_report(huge).valid?
  end
end
