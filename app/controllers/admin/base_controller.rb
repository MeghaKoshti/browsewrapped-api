module Admin
  # HTTP Basic auth from ADMIN_USER / ADMIN_PASSWORD. Without both, /admin
  # doesn't exist (404).
  #
  # Browsers resend Basic credentials on cross-site form posts, so every form
  # carries a token derived from the credentials (see #form_token) that
  # another site can't know.
  class BaseController < HtmlController
    before_action :require_admin_configured
    before_action :authenticate_admin

    helper_method :form_token

    private

    def require_admin_configured
      head :not_found if ENV["ADMIN_USER"].blank? || ENV["ADMIN_PASSWORD"].blank?
    end

    def authenticate_admin
      authenticate_or_request_with_http_basic("BrowseWrapped admin") do |user, password|
        # Both compared every time, so timing doesn't reveal which one was wrong.
        user_ok = ActiveSupport::SecurityUtils.secure_compare(user, ENV["ADMIN_USER"])
        password_ok = ActiveSupport::SecurityUtils.secure_compare(password, ENV["ADMIN_PASSWORD"])
        user_ok & password_ok
      end
    end

    def form_token
      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base,
                              "admin-form:#{ENV["ADMIN_USER"]}:#{ENV["ADMIN_PASSWORD"]}")
    end

    def verify_form_token
      return if ActiveSupport::SecurityUtils.secure_compare(params[:form_token].to_s, form_token)

      render plain: "Invalid form token. Reload the admin page and try again.", status: :unprocessable_entity
    end
  end
end
