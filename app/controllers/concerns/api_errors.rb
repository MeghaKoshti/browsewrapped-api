# Every API error uses one shape:
#
#   { "error": { "code": "not_found", "message": "Analysis not found" },
#     "error_message": "Analysis not found" }
#
# `code` is stable for clients to branch on; `message` is safe to show users.
# `error_message` repeats the message as a plain string for older clients.
module ApiErrors
  extend ActiveSupport::Concern

  included do
    rescue_from ActionController::BadRequest, ActionDispatch::Http::Parameters::ParseError do
      render_error :bad_request, "The request body could not be read.", :bad_request
    end

    rescue_from ActionController::ParameterMissing do |error|
      render_error :bad_request, error.message, :bad_request
    end

    rescue_from ActiveRecord::RecordNotFound do |error|
      render_error :not_found, "#{error.model&.underscore&.humanize || "Record"} not found", :not_found
    end

    # Raised by Rails' rate_limit (see ApplicationController).
    rescue_from ActionController::TooManyRequests do
      response.set_header("Retry-After", ApplicationController::RATE_LIMIT_WINDOW.to_i.to_s)
      render_error :rate_limited, "Too many requests. Please wait a minute and try again.", :too_many_requests
    end
  end

  private

  def render_error(code, message, status)
    render json: { error: { code: code.to_s, message: message }, error_message: message }, status: status
  end
end
