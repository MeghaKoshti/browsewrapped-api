# Who is calling, and do they have a Wrapped Pass?
#
#   before_action :require_session!  # 401 unauthorized without a valid bearer token
#   before_action :require_pass!     # 402 pass_required without an active Pass
module Entitlements
  extend ActiveSupport::Concern

  private

  # The signed-in email from "Authorization: Bearer <token>", or nil.
  def current_email
    return @current_email if defined?(@current_email)

    token = request.authorization.to_s[/\ABearer (.+)\z/, 1]
    @current_email = PassSession.email_for(token)
  end

  def pass_valid_until
    return @pass_valid_until if defined?(@pass_valid_until)

    @pass_valid_until = current_email && Purchase.pass_valid_until(current_email)
  end

  def pass?
    pass_valid_until.present?
  end

  def require_session!
    render_error(:unauthorized, "Please sign in again.", :unauthorized) unless current_email
  end

  def require_pass!
    render_error(:pass_required, "This feature needs a Wrapped Pass.", :payment_required) unless pass?
  end
end
