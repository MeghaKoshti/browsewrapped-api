# The interface every payment provider adapter implements.
#
#   create_checkout(email:, price:, success_url:, cancel_url:, metadata:) # => Checkout
#   verify_webhook!(headers, body)  # raises StandardWebhooks::InvalidSignature
#   parse_event(body)               # => Event
#
# `price` is a Billing::Pricing::Price (plan, currency, amount, early_bird);
# each adapter maps it to its own product ids.
module Billing
  class Provider
    # The provider failed to create a checkout (network, API error).
    class CheckoutError < Error; end
    # A verified webhook body we can't read.
    class InvalidPayload < Error; end

    Checkout = Data.define(:id, :url)

    # A provider event in our terms. `type` keeps the provider's name
    # ("payment.succeeded", "refund.succeeded"); anything else is ignored.
    Event = Data.define(:type, :email, :amount, :currency, :payment_ref, :plan, :partial) do
      def payment_succeeded? = type == "payment.succeeded"
      def refund_succeeded?  = type == "refund.succeeded"
    end

    def name
      self.class.name.demodulize.delete_suffix("Provider").underscore
    end

    def create_checkout(email:, price:, success_url:, cancel_url:, metadata: {})
      raise NotImplementedError
    end

    def verify_webhook!(headers, body)
      StandardWebhooks.verify!(secret: webhook_secret, headers: headers, body: body)
    end

    def parse_event(body)
      raise NotImplementedError
    end

    private

    def webhook_secret
      raise NotImplementedError
    end
  end
end
