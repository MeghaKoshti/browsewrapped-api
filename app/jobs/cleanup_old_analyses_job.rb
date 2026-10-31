# Deletes analyses (and any leftover uploads) older than Analysis::RETENTION.
# Scheduled in config/recurring.yml.
class CleanupOldAnalysesJob < ApplicationJob
  queue_as :default

  def perform
    Analysis.expired.find_each(&:purge!)
  end
end
