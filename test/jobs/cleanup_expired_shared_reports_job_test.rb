require "test_helper"

class CleanupExpiredSharedReportsJobTest < ActiveJob::TestCase
  test "deletes only expired shared reports" do
    expired = SharedReport.build_from_report({ "summary" => {} }).tap { |r| r.expires_at = 1.day.ago }
    expired.save!
    active = SharedReport.build_from_report({ "summary" => {} })
    active.save!

    CleanupExpiredSharedReportsJob.perform_now

    assert_not SharedReport.exists?(expired.id)
    assert SharedReport.exists?(active.id)
  end
end
