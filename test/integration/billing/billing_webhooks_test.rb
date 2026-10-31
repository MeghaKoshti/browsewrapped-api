require "test_helper"

class BillingWebhooksTest < ActionDispatch::IntegrationTest
  include BillingHelpers

  test "a valid payment.succeeded creates a Pass valid for 12 months" do
    post_webhook(payment_body(email: "Buyer@Example.com"))

    assert_response :success
    purchase = Purchase.sole
    assert_equal [ "buyer@example.com", "wrapped_pass", 500, "USD", "pay_123" ],
                 purchase.values_at(:email, :plan, :amount, :currency, :provider_ref)
    assert_in_delta 365.days.from_now, Purchase.pass_valid_until("buyer@example.com"), 5
  end

  test "a tampered body is rejected with 401" do
    headers = signed_headers(payment_body)

    post_webhook(payment_body(amount: 1), headers)

    assert_response :unauthorized
    assert_equal "invalid_signature", response.parsed_body.dig("error", "code")
    assert_equal 0, Purchase.count
  end

  test "a signature made with another secret is rejected" do
    other = "whsec_#{Base64.strict_encode64("x" * 32)}"

    post_webhook(payment_body, signed_headers(payment_body, secret: other))

    assert_response :unauthorized
  end

  test "an old or future timestamp is rejected" do
    post_webhook(payment_body, signed_headers(payment_body, timestamp: 6.minutes.ago.to_i))
    assert_response :unauthorized

    post_webhook(payment_body, signed_headers(payment_body, timestamp: 6.minutes.from_now.to_i))
    assert_response :unauthorized

    post_webhook(payment_body, signed_headers(payment_body, timestamp: 4.minutes.ago.to_i))
    assert_response :success
  end

  test "missing signature headers are rejected" do
    post_webhook(payment_body, {})

    assert_response :unauthorized
  end

  test "a duplicate delivery is acknowledged and ignored" do
    body = payment_body
    headers = signed_headers(body, id: "msg_1")

    post_webhook(body, headers)
    post_webhook(body, signed_headers(body, id: "msg_1"))

    assert_response :success
    assert response.parsed_body["duplicate"]
    assert_equal 1, Purchase.count
    assert_equal 1, BillingEvent.count
  end

  test "a second payment extends the Pass instead of overlapping" do
    post_webhook(payment_body(payment_id: "pay_1"))
    first_end = Purchase.pass_valid_until("buyer@example.com")

    post_webhook(payment_body(payment_id: "pay_2"))

    assert_in_delta first_end + 365.days, Purchase.pass_valid_until("buyer@example.com"), 1
  end

  test "refund.succeeded revokes the Pass" do
    post_webhook(payment_body)

    post_webhook(refund_body)

    assert_response :success
    assert Purchase.sole.revoked?
    assert_nil Purchase.pass_valid_until("buyer@example.com")
  end

  test "a partial refund keeps the Pass" do
    post_webhook(payment_body)

    post_webhook(refund_body(partial: true))

    assert_not Purchase.sole.revoked?
  end

  test "payments for other products and other event types are acknowledged and ignored" do
    post_webhook(payment_body(plan: "something_else"))
    assert_response :success

    body = JSON.generate(type: "dispute.opened", data: { payload_type: "Dispute", payment_id: "pay_9" })
    post_webhook(body)
    assert_response :success

    assert_equal 0, Purchase.count
    assert_equal 2, BillingEvent.count
  end

  test "a signed body that isn't JSON returns 400" do
    post_webhook("not json")

    assert_response :bad_request
  end
end
