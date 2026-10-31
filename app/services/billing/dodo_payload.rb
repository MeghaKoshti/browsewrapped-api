# Reads Dodo Payments webhook bodies:
#   { "business_id", "type", "timestamp", "data": { "payload_type": "Payment" | "Refund", ... } }
# https://docs.dodopayments.com/developer-resources/webhooks#webhook-payload-structure
# Payment fields (payment_id, total_amount, currency, customer.email, metadata,
# product_cart): https://docs.dodopayments.com/api-reference/payments/get-payments-1
# Refund fields (refund_id, payment_id, amount, is_partial):
# https://docs.dodopayments.com/api-reference/refunds/get-refunds-1
#
# The fake provider sends the same shape, so this code runs in development too.
module Billing
  module DodoPayload
    module_function

    def parse(body, product_ids: [])
      json = JSON.parse(body)
      data = json["data"]
      raise Provider::InvalidPayload, "Missing data" unless json.is_a?(Hash) && data.is_a?(Hash)

      metadata = data["metadata"].is_a?(Hash) ? data["metadata"] : {}
      Provider::Event.new(
        type:        json["type"].to_s,
        email:       EmailAddress.normalize(metadata["email"].presence || data.dig("customer", "email")),
        amount:      data["total_amount"] || data["amount"],
        currency:    data["currency"],
        payment_ref: data["payment_id"],
        plan:        metadata["plan"].presence || plan_from_products(data["product_cart"], product_ids),
        partial:     data["is_partial"] == true
      )
    rescue JSON::ParserError
      raise Provider::InvalidPayload, "Body is not JSON"
    end

    def plan_from_products(cart, product_ids)
      ids = Array(cart).filter_map { |item| item["product_id"] if item.is_a?(Hash) }
      Pricing::PLAN if ids.intersect?(product_ids.compact)
    end
  end
end
