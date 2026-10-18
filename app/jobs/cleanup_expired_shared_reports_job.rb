# Deletes shared reports past their 30-day expiry. Scheduled in config/recurring.yml.
class CleanupExpiredSharedReportsJob < ApplicationJob
  queue_as :default

  def perform
    SharedReport.expired.in_batches.delete_all
  end
end
