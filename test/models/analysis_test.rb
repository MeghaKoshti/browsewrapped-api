require "test_helper"

class AnalysisTest < ActiveSupport::TestCase
  test "starts as pending with a uuid id" do
    analysis = Analysis.create!

    assert analysis.pending?
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, analysis.id)
  end

  test "rejects unknown statuses" do
    analysis = Analysis.new(status: "exploded")

    assert_not analysis.valid?
  end

  test "as_api_json includes the result only when completed and the error only when failed" do
    completed = Analysis.new(id: SecureRandom.uuid, status: :completed, result: { "a" => 1 }, created_at: Time.current)
    failed    = Analysis.new(id: SecureRandom.uuid, status: :failed, error_message: "boom", created_at: Time.current)
    pending   = Analysis.new(id: SecureRandom.uuid, status: :pending, created_at: Time.current)

    assert_equal({ "a" => 1 }, completed.as_api_json[:result])
    assert_equal "boom", failed.as_api_json[:error_message]
    assert_not pending.as_api_json.key?(:result)
    assert_not pending.as_api_json.key?(:error_message)
  end
end
