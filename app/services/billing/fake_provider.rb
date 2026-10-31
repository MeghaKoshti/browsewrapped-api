# A stand-in payment provider for development and tests. Its checkout URL is a
# tiny page served by this API (FakeCheckoutsController) with "Pay (fake)" and
# "Cancel" buttons. Paying sends a correctly signed, Dodo-shaped
# payment.succeeded webhook to our own webhook endpoint, so the real
# verification and fulfilment code runs end to end.
module Billing
  class FakeProvider < Provider
    PURPOSE = :fake_checkout

    def self.enabled?
      !Rails.env.production?
    end

    def self.webhook_secret
      key = Rails.application.key_generator.generate_key("fake billing webhook secret", 32)
      "whsec_#{Base64.strict_encode64(key)}"
    end

    # Checkout details travel in a signed, expiring token instead of a table.
    def self.verifier
      ActiveSupport::MessageVerifier.new(
        Rails.application.key_generator.generate_key("fake checkout token", 32),
        url_safe: true, serializer: JSON
      )
    end

    # => Hash with string keys, or nil when the token is forged or expired.
    def self.read_checkout(token)
      verifier.verified(token.to_s, purpose: PURPOSE)
    end

    def create_checkout(email:, price:, success_url:, cancel_url:, metadata: {})
      details = { "email" => email, "plan" => price.plan, "currency" => price.currency, "amount" => price.amount,
                  "success_url" => success_url, "cancel_url" => cancel_url, "metadata" => metadata.stringify_keys }
      token = self.class.verifier.generate(details, purpose: PURPOSE, expires_in: 1.hour)
      Checkout.new(id: token, url: AppUrls.api("/api/v1/fake_checkout/#{token}"))
    end

    # The body and signed headers of the webhook a real provider would send
    # after this checkout was paid.
    def payment_webhook(checkout)
      body = JSON.generate(
        business_id: "bus_fake",
        type:        "payment.succeeded",
        timestamp:   Time.current.utc.iso8601,
        data: {
          payload_type: "Payment",
          payment_id:   "pay_fake_#{SecureRandom.hex(8)}",
          total_amount: checkout["amount"],
          currency:     checkout["currency"],
          status:       "succeeded",
          customer:     { email: checkout["email"] },
          metadata:     checkout["metadata"]
        }
      )
      [ StandardWebhooks.headers_for(secret: webhook_secret, body: body), body ]
    end

    def parse_event(body)
      DodoPayload.parse(body)
    end

    private

    def webhook_secret
      self.class.webhook_secret
    end
  end
end
