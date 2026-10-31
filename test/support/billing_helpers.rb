# Helpers for billing tests: Dodo-shaped webhook bodies signed like the real thing.
module BillingHelpers
  def with_env(values)
    originals = values.keys.index_with { |key| ENV[key] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    originals.each { |key, value| ENV[key] = value }
  end

  def payment_body(email: "buyer@example.com", payment_id: "pay_123", amount: 500, currency: "USD", plan: "wrapped_pass")
    JSON.generate(business_id: "bus_1", type: "payment.succeeded", timestamp: Time.current.iso8601,
                  data: { payload_type: "Payment", payment_id: payment_id, total_amount: amount, currency: currency,
                          customer: { email: email, name: "Buyer" }, metadata: { plan: plan, email: email } })
  end

  def refund_body(payment_id: "pay_123", partial: false)
    JSON.generate(business_id: "bus_1", type: "refund.succeeded", timestamp: Time.current.iso8601,
                  data: { payload_type: "Refund", refund_id: "ref_1", payment_id: payment_id, is_partial: partial,
                          amount: 500, currency: "USD", customer: { email: "buyer@example.com" } })
  end

  def signed_headers(body, secret: Billing::FakeProvider.webhook_secret, **options)
    Billing::StandardWebhooks.headers_for(secret: secret, body: body, **options)
  end

  def post_webhook(body, headers = signed_headers(body))
    post "/api/v1/webhooks/billing", params: body, headers: headers.merge("Content-Type" => "application/json")
  end

  def with_rails_env(name)
    original = Rails.env
    Rails.env = name
    yield
  ensure
    Rails.env = original
  end
end
