# The hosted "checkout page" of Billing::FakeProvider. 404 in production.
#
# Paying posts a signed payment.succeeded webhook through the whole Rack app
# (routing, signature check, Billing::WebhookProcessor), exactly as the real
# provider would, but in-process: a dev server calling itself over HTTP could
# deadlock with a single Puma thread.
class FakeCheckoutsController < HtmlController
  before_action :require_fake_billing
  before_action :load_checkout

  # GET /api/v1/fake_checkout/:id
  def show; end

  # POST /api/v1/fake_checkout/:id/pay
  def pay
    headers, body = Billing::FakeProvider.new.payment_webhook(@checkout)
    status, = deliver_webhook(headers, body)
    return render(plain: "The fake webhook was rejected (HTTP #{status}).", status: :bad_gateway) unless status == 200

    redirect_to success_url, allow_other_host: true
  end

  # POST /api/v1/fake_checkout/:id/cancel
  def cancel
    redirect_to @checkout["cancel_url"], allow_other_host: true
  end

  private

  def require_fake_billing
    head :not_found unless Billing::FakeProvider.enabled?
  end

  def load_checkout
    @checkout = Billing::FakeProvider.read_checkout(params[:id])
    render plain: "This checkout has expired.", status: :not_found unless @checkout
  end

  def success_url
    "#{@checkout["success_url"]}?#{{ email: @checkout["email"] }.to_query}"
  end

  def deliver_webhook(headers, body)
    env = Rack::MockRequest.env_for(
      "/api/v1/webhooks/billing",
      method: "POST", input: body, "CONTENT_TYPE" => "application/json",
      "REMOTE_ADDR" => request.remote_ip, "HTTP_HOST" => request.host_with_port,
      **headers.transform_keys { |name| "HTTP_#{name.upcase.tr("-", "_")}" }
    )
    Rails.application.call(env)
  end
end
