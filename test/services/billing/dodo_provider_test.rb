require "test_helper"

class DodoProviderTest < ActiveSupport::TestCase
  ENV_VARS = {
    "DODO_API_KEY" => "sk_test", "DODO_ENVIRONMENT" => "test_mode",
    "DODO_PRODUCT_PASS_USD" => "pdt_usd", "DODO_PRODUCT_PASS_INR" => "pdt_inr",
    "DODO_EARLY_BIRD_DISCOUNT_CODE" => "EARLYBIRD", "DODO_WEBHOOK_SECRET" => "whsec_#{Base64.strict_encode64("k" * 32)}"
  }.freeze

  # Records the request and answers with a canned response.
  class FakeTransport
    attr_reader :requests

    def initialize(status: 200, body: '{"session_id":"cks_1","checkout_url":"https://test.checkout.dodopayments.com/session/cks_1"}')
      @status, @body, @requests = status, body, []
    end

    def call(uri, headers, body)
      @requests << { uri: uri.to_s, headers: headers, body: JSON.parse(body) }
      [ @status, @body ]
    end
  end

  def provider(transport = FakeTransport.new, env: ENV_VARS)
    Billing::DodoProvider.new(env: env, transport: transport)
  end

  def price(early_bird: false)
    Billing::Pricing::Price.new(plan: "wrapped_pass", currency: "USD", amount: 500, early_bird: early_bird)
  end

  def checkout(provider_instance, early_bird: false)
    provider_instance.create_checkout(email: "a@b.co", price: price(early_bird: early_bird),
                                      success_url: "https://web/billing/success", cancel_url: "https://web/billing/cancel",
                                      metadata: { plan: "wrapped_pass", email: "a@b.co" })
  end

  test "creates a checkout session for the configured product" do
    transport = FakeTransport.new

    result = checkout(provider(transport))

    assert_equal "https://test.checkout.dodopayments.com/session/cks_1", result.url
    request = transport.requests.sole
    assert_equal "https://test.dodopayments.com/checkouts", request[:uri]
    assert_equal "Bearer sk_test", request[:headers]["Authorization"]
    assert_equal [ { "product_id" => "pdt_usd", "quantity" => 1 } ], request[:body]["product_cart"]
    assert_equal({ "email" => "a@b.co" }, request[:body]["customer"])
    assert_equal "https://web/billing/success", request[:body]["return_url"]
    assert_equal({ "plan" => "wrapped_pass", "email" => "a@b.co" }, request[:body]["metadata"])
    assert_not request[:body].key?("discount_codes")
  end

  test "applies the early-bird discount code" do
    transport = FakeTransport.new

    checkout(provider(transport), early_bird: true)

    assert_equal [ "EARLYBIRD" ], transport.requests.sole[:body]["discount_codes"]
  end

  test "live mode uses the live API" do
    transport = FakeTransport.new

    checkout(provider(transport, env: ENV_VARS.merge("DODO_ENVIRONMENT" => "live_mode")))

    assert_equal "https://live.dodopayments.com/checkouts", transport.requests.sole[:uri]
  end

  test "an API error raises a checkout error" do
    assert_raises(Billing::Provider::CheckoutError) { checkout(provider(FakeTransport.new(status: 422, body: "{}"))) }
  end

  test "missing configuration raises a config error before any request" do
    transport = FakeTransport.new

    assert_raises(Billing::ConfigError) { checkout(provider(transport, env: ENV_VARS.except("DODO_API_KEY"))) }
    assert_raises(Billing::ConfigError) { checkout(provider(transport, env: ENV_VARS.except("DODO_EARLY_BIRD_DISCOUNT_CODE")), early_bird: true) }
    assert_empty transport.requests
  end

  test "parses a Dodo payment.succeeded payload" do
    body = { business_id: "bus_1", type: "payment.succeeded", timestamp: "2026-10-24T10:00:00Z",
             data: { payload_type: "Payment", payment_id: "pay_1", total_amount: 19_900, currency: "INR",
                     customer: { customer_id: "cus_1", email: "Buyer@Example.com", name: "B" },
                     metadata: {}, product_cart: [ { product_id: "pdt_inr", quantity: 1 } ] } }.to_json

    event = provider.parse_event(body)

    assert event.payment_succeeded?
    assert_equal [ "buyer@example.com", 19_900, "INR", "pay_1", "wrapped_pass" ],
                 [ event.email, event.amount, event.currency, event.payment_ref, event.plan ]
  end

  test "verifies webhooks with DODO_WEBHOOK_SECRET" do
    body = '{"type":"payment.succeeded","data":{}}'
    headers = Billing::StandardWebhooks.headers_for(secret: ENV_VARS["DODO_WEBHOOK_SECRET"], body: body)

    assert provider.verify_webhook!(headers, body)
    assert_raises(Billing::StandardWebhooks::InvalidSignature) { provider.verify_webhook!(headers, "#{body} ") }
  end

  test "BILLING_PROVIDER picks the adapter, and fake is refused in production" do
    original = ENV["BILLING_PROVIDER"]
    ENV["BILLING_PROVIDER"] = "dodo"
    assert_instance_of Billing::DodoProvider, Billing.provider
    ENV["BILLING_PROVIDER"] = "fake"
    assert_instance_of Billing::FakeProvider, Billing.provider

    Rails.env = "production"
    assert_raises(Billing::ConfigError) { Billing.provider }
  ensure
    Rails.env = "test"
    ENV["BILLING_PROVIDER"] = original
  end
end
