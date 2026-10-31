# Applies a verified provider event exactly once.
#
# The BillingEvent row and its effect are written in one transaction: a
# duplicate delivery hits the unique index and changes nothing, and a failure
# rolls both back so the provider's retry processes it again.
module Billing
  module WebhookProcessor
    module_function

    # => :processed or :duplicate
    def call(provider:, event_id:, event:)
      BillingEvent.transaction do
        BillingEvent.create!(provider: provider, provider_event_id: event_id,
                             event_type: event.type.presence || "unknown", payment_ref: event.payment_ref)
        apply(provider, event)
      end
      :processed
    rescue ActiveRecord::RecordNotUnique
      :duplicate
    end

    def apply(provider, event)
      if event.payment_succeeded? && event.plan == Pricing::PLAN
        raise Provider::InvalidPayload, "Payment without email or id" if event.email.blank? || event.payment_ref.blank?

        Purchase.record_payment!(email: event.email, plan: event.plan, amount: event.amount, currency: event.currency,
                                 provider: provider, provider_ref: event.payment_ref)
      elsif event.refund_succeeded? && !event.partial
        # A partial refund is a goodwill gesture; the buyer keeps the Pass.
        Purchase.where(provider: provider, provider_ref: event.payment_ref).find_each(&:revoke!)
      end
    end
  end
end
