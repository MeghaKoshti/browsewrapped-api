require "test_helper"

class StandardWebhooksTest < ActiveSupport::TestCase
  # Test vector from the Standard Webhooks reference libraries
  # (https://github.com/standard-webhooks/standard-webhooks), the scheme Dodo uses.
  SECRET = "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw".freeze
  ID = "msg_p5jXN8AQM9LWM0D4loKWxJek".freeze
  TIMESTAMP = 1_614_265_330
  BODY = '{"test": 2432232314}'.freeze
  SIGNATURE = "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=".freeze

  test "signs like the reference implementation" do
    assert_equal SIGNATURE, Billing::StandardWebhooks.sign(secret: SECRET, id: ID, timestamp: TIMESTAMP, body: BODY)
  end

  test "accepts any of several space-separated signatures" do
    headers = { "webhook-id" => ID, "webhook-timestamp" => TIMESTAMP.to_s, "webhook-signature" => "v1,bm9wZQ== #{SIGNATURE}" }

    assert Billing::StandardWebhooks.verify!(secret: SECRET, headers: headers, body: BODY, now: Time.at(TIMESTAMP))
  end

  test "rejects a missing secret" do
    headers = { "webhook-id" => ID, "webhook-timestamp" => TIMESTAMP.to_s, "webhook-signature" => SIGNATURE }

    assert_raises(Billing::StandardWebhooks::InvalidSignature) do
      Billing::StandardWebhooks.verify!(secret: nil, headers: headers, body: BODY, now: Time.at(TIMESTAMP))
    end
  end
end
