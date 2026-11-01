require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper
  include BillingHelpers

  def request_link(email = "buyer@example.com")
    post "/api/v1/sessions/magic_link", params: { email: email }, as: :json
  end

  def token_from_last_email
    mail = ActionMailer::Base.deliveries.last
    mail.text_part.body.to_s[%r{/auth/verify\?token=(\S+)}, 1]
  end

  def verify(token)
    post "/api/v1/sessions/verify", params: { token: token }, as: :json
    response.parsed_body
  end

  def sign_in(email = "buyer@example.com")
    perform_enqueued_jobs { request_link(email) }
    verify(token_from_last_email)["access_token"]
  end

  test "requesting a link emails a single-use sign-in link to the web app" do
    perform_enqueued_jobs { request_link(" Buyer@Example.com ") }

    assert_response :accepted
    mail = ActionMailer::Base.deliveries.sole
    assert_equal [ "buyer@example.com" ], mail.to
    assert_match %r{http://localhost:5173/auth/verify\?token=\w{32}}, mail.html_part.body.to_s
    assert_match %r{http://localhost:5173/auth/verify\?token=\w{32}}, mail.text_part.body.to_s
    token = token_from_last_email
    assert_not MagicLinkToken.exists?(token_digest: token)
    assert MagicLinkToken.exists?(token_digest: MagicLinkToken.digest(token))
  end

  test "the token never goes through the job queue" do
    assert_no_enqueued_jobs { request_link }

    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  test "an email failure still answers 202" do
    original = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :smtp
    ActionMailer::Base.smtp_settings = { address: "127.0.0.1", port: 1, open_timeout: 1 }

    request_link

    assert_response :accepted
  ensure
    ActionMailer::Base.delivery_method = original
  end

  test "the response is the same for unknown, invalid and paying emails" do
    Purchase.record_payment!(email: "payer@example.com", plan: "wrapped_pass", amount: 500, currency: "USD", provider: "fake", provider_ref: "p1")

    bodies = [ "payer@example.com", "stranger@example.com", "not-an-email" ].map do |email|
      request_link(email)
      [ response.status, response.body ]
    end

    assert_equal 1, bodies.uniq.size
    assert_equal 202, bodies.first.first
  end

  test "verify returns an access token and the Pass end date" do
    Purchase.record_payment!(email: "buyer@example.com", plan: "wrapped_pass", amount: 500, currency: "USD", provider: "fake", provider_ref: "p1")
    perform_enqueued_jobs { request_link }

    body = verify(token_from_last_email)

    assert_response :success
    assert_equal "buyer@example.com", body["email"]
    assert_equal Purchase.pass_valid_until("buyer@example.com").iso8601, body["pass_valid_until"]
    assert_equal "buyer@example.com", PassSession.email_for(body["access_token"])
  end

  test "a link works only once" do
    perform_enqueued_jobs { request_link }
    token = token_from_last_email

    verify(token)
    assert_response :success

    body = verify(token)
    assert_response :unauthorized
    assert_equal "invalid_or_expired_token", body.dig("error", "code")
  end

  test "a link expires after 15 minutes" do
    perform_enqueued_jobs { request_link }
    token = token_from_last_email

    travel 16.minutes do
      verify(token)
      assert_response :unauthorized
    end
  end

  test "unknown tokens are rejected" do
    verify("nope")
    assert_response :unauthorized
    verify("")
    assert_response :unauthorized
  end

  test "magic links are rate limited per email without telling the caller" do
    ApplicationController::MAGIC_LINK_EMAIL_RATE_LIMIT.times do |i|
      post "/api/v1/sessions/magic_link", params: { email: "victim@example.com" }, as: :json,
                                          headers: { "REMOTE_ADDR" => "10.0.0.#{i + 1}" }
    end
    assert_no_emails do
      post "/api/v1/sessions/magic_link", params: { email: "victim@example.com" }, as: :json, headers: { "REMOTE_ADDR" => "10.0.1.1" }
    end

    assert_response :accepted
  end

  test "magic links are rate limited per IP" do
    ApplicationController::MAGIC_LINK_IP_RATE_LIMIT.times { |i| request_link("user#{i}@example.com") }

    request_link("another@example.com")

    assert_response :too_many_requests
  end

  test "GET /api/v1/me needs a valid token" do
    get "/api/v1/me"
    assert_response :unauthorized

    get "/api/v1/me", headers: { "Authorization" => "Bearer forged" }
    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body.dig("error", "code")
  end

  test "GET /api/v1/me shows the Pass once the payment has landed" do
    token = sign_in

    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
    assert_equal({ "email" => "buyer@example.com", "pass_valid_until" => nil, "has_pass" => false }, response.parsed_body)

    post_webhook(payment_body)
    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
    assert response.parsed_body["has_pass"]
    assert response.parsed_body["pass_valid_until"].present?

    post_webhook(refund_body)
    get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
    assert_not response.parsed_body["has_pass"]
  end

  test "access tokens expire after 30 days" do
    token = sign_in

    travel 31.days do
      get "/api/v1/me", headers: { "Authorization" => "Bearer #{token}" }
      assert_response :unauthorized
    end
  end
end
