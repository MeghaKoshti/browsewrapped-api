# A webhook we have already processed. The unique (provider, provider_event_id)
# index is what makes retried deliveries harmless.
class BillingEvent < ApplicationRecord
  validates :provider, :provider_event_id, :event_type, presence: true
end
