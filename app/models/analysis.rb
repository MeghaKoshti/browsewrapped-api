# One history-analysis run. Large uploads are analysed in the background by
# AnalyzeHistoryJob; the client polls GET /api/v1/analyses/:id for the result.
class Analysis < ApplicationRecord
  include DeleteToken

  RETENTION = 7.days

  enum :status, {
    pending:    "pending",
    processing: "processing",
    completed:  "completed",
    failed:     "failed"
  }, default: "pending", validate: true

  scope :expired, -> { where(created_at: ...RETENTION.ago) }

  # Removes the report and any upload still waiting for the job.
  def purge!
    AnalysisUpload.delete(id)
    destroy!
  end

  def finished?
    completed? || failed?
  end

  def as_api_json
    json = { id: id, status: status, filename: filename, created_at: created_at.iso8601 }
    json[:result]        = result        if completed?
    json[:error_message] = error_message if failed?
    json
  end
end
