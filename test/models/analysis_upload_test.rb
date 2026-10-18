require "test_helper"

class AnalysisUploadTest < ActiveSupport::TestCase
  test "stores, reads and deletes an upload by analysis id" do
    id = SecureRandom.uuid

    AnalysisUpload.write(id, "hello")
    assert_equal "hello", AnalysisUpload.read(id)

    AnalysisUpload.delete(id)
    assert_not AnalysisUpload.exist?(id)
  end

  test "refuses ids that are not UUIDs" do
    assert_raises(ArgumentError) { AnalysisUpload.path_for("../../etc/passwd") }
  end
end
