require "base64"
require "openssl"

# Signs and verifies webhooks with the Standard Webhooks scheme, which Dodo
# Payments (and Polar) use:
#   https://www.standardwebhooks.com/
#   https://docs.dodopayments.com/developer-resources/webhooks#manual-verification-alternative
#
# signed content = "#{webhook-id}.#{webhook-timestamp}.#{raw body}"
# signature      = "v1," + base64(HMAC-SHA256(base64-decoded secret without "whsec_", content))
# The webhook-signature header may hold several space-separated signatures
# (during secret rotation); any match is enough.
module Billing
  module StandardWebhooks
    class InvalidSignature < Error; end

    HEADERS = %w[webhook-id webhook-timestamp webhook-signature].freeze
    TOLERANCE = 5.minutes

    module_function

    def sign(secret:, id:, timestamp:, body:)
      digest = OpenSSL::HMAC.digest("SHA256", signing_key(secret), "#{id}.#{timestamp}.#{body}")
      "v1,#{Base64.strict_encode64(digest)}"
    end

    # Headers for a body signed now; used by the fake provider and tests.
    def headers_for(secret:, body:, id: "msg_#{SecureRandom.hex(12)}", timestamp: Time.current.to_i)
      { "webhook-id" => id, "webhook-timestamp" => timestamp.to_s,
        "webhook-signature" => sign(secret: secret, id: id, timestamp: timestamp, body: body) }
    end

    def verify!(secret:, headers:, body:, now: Time.current)
      id, timestamp, signatures = HEADERS.map { |name| headers[name].to_s }
      raise InvalidSignature, "Missing webhook headers" if [ id, timestamp, signatures ].any?(&:empty?)
      raise InvalidSignature, "Bad timestamp" unless timestamp.match?(/\A\d+\z/)
      raise InvalidSignature, "Timestamp outside tolerance" if (now.to_i - timestamp.to_i).abs > TOLERANCE

      expected = sign(secret: secret, id: id, timestamp: timestamp, body: body)
      valid = signatures.split(" ").any? { |candidate| ActiveSupport::SecurityUtils.secure_compare(candidate, expected) }
      raise InvalidSignature, "Signature mismatch" unless valid

      true
    end

    def signing_key(secret)
      raise InvalidSignature, "Webhook secret is not configured" if secret.blank?

      Base64.strict_decode64(secret.delete_prefix("whsec_"))
    rescue ArgumentError
      raise InvalidSignature, "Webhook secret is not valid base64"
    end
  end
end
