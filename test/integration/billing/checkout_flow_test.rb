require "test_helper"

class CheckoutFlowTest < ActionDispatch::IntegrationTest
  include BillingHelpers

  def checkout!(params = { email: "Buyer@Example.com ", currency: "INR" })
    post "/api/v1/checkouts", params: params, as: :json
    response.parsed_body
  end

  test "GET /api/v1/pricing returns the plan, both currencies and the early-bird deadline" do
    with_env("EARLY_BIRD_UNTIL" => "2026-12-15T23:59:59Z") { get "/api/v1/pricing" }

    assert_response :success
    assert_equal({ "plan" => "wrapped_pass",
                   "prices" => { "INR" => { "amount" => 19_900, "early_bird_amount" => 9_900 },
                                 "USD" => { "amount" => 500, "early_bird_amount" => 300 } },
                   "early_bird_until" => "2026-12-15T23:59:59Z", "valid_days" => 365 }, response.parsed_body)
  end

  test "the early bird can be switched off" do
    with_env("EARLY_BIRD_UNTIL" => "off") { get "/api/v1/pricing" }

    assert_nil response.parsed_body["early_bird_until"]
  end

  test "checkout uses the early-bird price before the deadline and the full price after" do
    with_env("EARLY_BIRD_UNTIL" => 1.day.from_now.utc.iso8601) do
      assert_equal 9_900, Billing::Pricing.price_for("INR").amount
    end
    with_env("EARLY_BIRD_UNTIL" => 1.day.ago.utc.iso8601) do
      assert_equal 19_900, Billing::Pricing.price_for("INR").amount
      assert_not Billing::Pricing.price_for("INR").early_bird
    end
  end

  test "POST /api/v1/checkouts returns a fake checkout URL in tests" do
    body = checkout!

    assert_response :created
    assert_match %r{\Ahttp://localhost:3000/api/v1/fake_checkout/.+}, body["checkout_url"]
  end

  test "an invalid email is rejected" do
    body = checkout!(email: "not-an-email", currency: "USD")

    assert_response :unprocessable_entity
    assert_equal "invalid_email", body.dig("error", "code")
  end

  test "an unknown currency or plan is rejected" do
    assert_equal "invalid_currency", checkout!(email: "a@b.co", currency: "EUR").dig("error", "code")
    assert_equal "invalid_plan", checkout!(email: "a@b.co", currency: "USD", plan: "lifetime").dig("error", "code")
  end

  test "the client can't choose the price" do
    with_env("EARLY_BIRD_UNTIL" => "off") do
      body = checkout!(email: "a@b.co", currency: "USD", amount: 1)
      checkout = Billing::FakeProvider.read_checkout(body["checkout_url"].split("/").last)
      assert_equal 500, checkout["amount"]
    end
  end

  test "fake checkout: pay sends a signed webhook and the Pass is recorded" do
    url = checkout!["checkout_url"]
    get URI(url).path
    assert_response :success
    assert_includes response.body, "Pay (fake)"

    post "#{URI(url).path}/pay"

    assert_response :redirect
    location = URI(response.location)
    assert_equal "http://localhost:5173/billing/success", location.to_s.split("?").first
    query = Rack::Utils.parse_query(location.query)
    assert_equal "buyer@example.com", query["email"]
    assert_equal "buyer@example.com", MagicLinkToken.redeem(query["token"])
    purchase = Purchase.sole
    assert_equal "buyer@example.com", purchase.email
    assert_equal "fake", purchase.provider
    assert_equal "INR", purchase.currency
    assert_in_delta 365.days.from_now, purchase.valid_until, 5
    assert_equal 1, BillingEvent.count
  end

  test "fake checkout: cancel goes back to the web app without paying" do
    path = URI(checkout!["checkout_url"]).path

    post "#{path}/cancel"

    assert_redirected_to "http://localhost:5173/billing/cancel"
    assert_equal 0, Purchase.count
  end

  test "fake checkout links can't be forged" do
    get "/api/v1/fake_checkout/forged"
    assert_response :not_found

    post "/api/v1/fake_checkout/forged/pay"
    assert_response :not_found
    assert_equal 0, Purchase.count
  end

  test "the fake checkout is not available in production" do
    path = URI(checkout!["checkout_url"]).path

    with_rails_env("production") { get path }

    assert_response :not_found
  end

  test "checkouts are rate limited per IP" do
    ApplicationController::CHECKOUT_RATE_LIMIT.times { checkout!(email: "x", currency: "USD") }

    checkout!

    assert_response :too_many_requests
  end
end
