module Api
  module V1
    # POST /api/v1/webhooks/billing
    # Verifies the Standard Webhooks signature over the raw body, then applies
    # the event once (see Billing::WebhookProcessor). Answers 200 for
    # duplicates and for events we don't use, so the provider stops retrying.
    class BillingWebhooksController < ApplicationController
      wrap_parameters false

      def create
        provider = Billing.provider
        headers  = Billing::StandardWebhooks::HEADERS.index_with { |name| request.headers[name] }
        body     = request.raw_post

        provider.verify_webhook!(headers, body)
        result = Billing::WebhookProcessor.call(provider: provider.name, event_id: headers["webhook-id"],
                                                event: provider.parse_event(body))

        render json: { received: true, duplicate: result == :duplicate }
      rescue Billing::StandardWebhooks::InvalidSignature => e
        Rails.logger.warn("Rejected billing webhook: #{e.message}")
        render_error :invalid_signature, "Invalid webhook signature", :unauthorized
      rescue Billing::Provider::InvalidPayload => e
        render_error :invalid_payload, e.message, :bad_request
      end
    end
  end
end
