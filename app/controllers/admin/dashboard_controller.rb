module Admin
  # GET /admin: today's numbers at a glance (UTC day).
  class DashboardController < BaseController
    def show
      today = Time.current.utc.all_day
      @analyses_by_status = Analysis.where(created_at: today).group(:status).count
      @failures = Analysis.failed.where(created_at: 7.days.ago..).group(:error_message).order(count_all: :desc).limit(10).count
      @shares_today = SharedReport.where(created_at: today).count
      @active_shares = SharedReport.active.count
      @sales_today = Purchase.where(created_at: today, revoked_at: nil).group(:currency).sum(:amount)
      @sales_count_today = Purchase.where(created_at: today, revoked_at: nil).count
      @active_passes = Purchase.active.distinct.count(:email)
      @ai_used = AiBudget.used_today
      @ai_limit = AiBudget.daily_limit
      @recent_categories = DomainCategory.order(updated_at: :desc).limit(30)
      @categories = UrlCategorizer::CATEGORY_COLORS.keys
    end
  end
end
