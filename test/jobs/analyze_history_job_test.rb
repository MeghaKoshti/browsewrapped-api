require "test_helper"

class AnalyzeHistoryJobTest < ActiveJob::TestCase
  def build_analysis(content)
    analysis = Analysis.create!(filename: "history.json")
    AnalysisUpload.write(analysis.id, content)
    analysis
  end

  test "analyses the upload, stores the result and deletes the file" do
    analysis = build_analysis(File.read(Rails.root.join("sample/sample_history.json")))

    AnalyzeHistoryJob.perform_now(analysis.id)

    analysis.reload
    assert analysis.completed?
    assert_operator analysis.entries_count, :>, 0
    assert_equal "upload", analysis.result.dig("meta", "source")
    assert analysis.result.key?("persona")
    assert_not AnalysisUpload.exist?(analysis.id)
  end

  test "marks the analysis failed with a readable message for an unsupported file" do
    analysis = build_analysis("just some text")

    AnalyzeHistoryJob.perform_now(analysis.id)

    analysis.reload
    assert analysis.failed?
    assert_match(/Unsupported format/, analysis.error_message)
    assert_nil analysis.result
    assert_not AnalysisUpload.exist?(analysis.id)
  end

  test "marks the analysis failed when the file has no usable entries" do
    analysis = build_analysis('[{"url": "chrome://settings", "title": "Settings"}]')

    AnalyzeHistoryJob.perform_now(analysis.id)

    assert analysis.reload.failed?
    assert_equal AnalyzeHistoryJob::NO_ENTRIES_MESSAGE, analysis.error_message
  end

  test "marks the analysis failed when the upload is missing" do
    analysis = Analysis.create!

    AnalyzeHistoryJob.perform_now(analysis.id)

    assert analysis.reload.failed?
    assert_match(/no longer available/, analysis.error_message)
  end

  test "does nothing for an analysis that already finished" do
    analysis = Analysis.create!(status: :completed, result: { "summary" => {} })

    AnalyzeHistoryJob.perform_now(analysis.id)

    assert_equal({ "summary" => {} }, analysis.reload.result)
  end
end
