# Parses and analyses an uploaded history file outside the request cycle.
#
# Idempotent: a finished analysis is never processed twice. Any error marks the
# analysis as failed with a readable message, and the upload is always deleted.
class AnalyzeHistoryJob < ApplicationJob
  queue_as :default

  NO_ENTRIES_MESSAGE = "No valid browser history entries found in the file".freeze

  # The upload request waits for a sync run, so the LLM gets at most this long.
  SYNC_AI_BUDGET_SECONDS = 5

  def perform(analysis_id, sync: false)
    analysis = Analysis.find_by(id: analysis_id)
    return if analysis.nil? || analysis.finished?

    analysis.update!(status: :processing)
    entries = HistoryParser.parse_file(AnalysisUpload.path_for(analysis.id))

    if entries.empty?
      analysis.update!(status: :failed, error_message: NO_ENTRIES_MESSAGE)
      return
    end

    ai     = AiDomainCategorizer.new(entries, time_budget: (SYNC_AI_BUDGET_SECONDS if sync)).call
    result = HistoryAnalyzer.new(entries, domain_overrides: ai.overrides).analyze
    result[:meta] = {
      total_entries_parsed:  entries.size,
      source:                analysis.source,
      processed_at:          Time.current.iso8601,
      analysis_id:           analysis.id,
      ai_classified_domains: ai.ai_classified
    }

    analysis.update!(status: :completed, result: result, entries_count: entries.size, error_message: nil)
  rescue => e
    Rails.logger.error("AnalyzeHistoryJob #{analysis_id} failed: #{e.class}: #{e.message}")
    analysis&.update_columns(status: "failed", error_message: readable_error(e), updated_at: Time.current)
  ensure
    AnalysisUpload.delete(analysis.id) if analysis
  end

  private

  def readable_error(error)
    case error
    when Errno::ENOENT then "The uploaded file is no longer available. Please upload it again."
    when HistoryParser::UnsupportedFormatError then error.message
    else "Something went wrong while analysing your history. Please try again."
    end
  end
end
