require "test_helper"

class CleanupOldAnalysesJobTest < ActiveJob::TestCase
  test "deletes analyses older than the retention period and keeps recent ones" do
    old    = Analysis.create!(created_at: 8.days.ago)
    recent = Analysis.create!(created_at: 1.day.ago)
    AnalysisUpload.write(old.id, "leftover")

    CleanupOldAnalysesJob.perform_now

    assert_not Analysis.exists?(old.id)
    assert Analysis.exists?(recent.id)
    assert_not AnalysisUpload.exist?(old.id)
  end
end
