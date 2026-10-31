# Plan and prices come from here, never from the client.
# Amounts are in the smallest currency unit (paise, cents).
module Billing
  module Pricing
    PLAN = "wrapped_pass".freeze
    VALID_DAYS = 365
    PRICES = {
      "INR" => { amount: 19_900, early_bird_amount: 9_900 },
      "USD" => { amount: 500, early_bird_amount: 300 }
    }.freeze
    DEFAULT_EARLY_BIRD_UNTIL = "2026-12-15T23:59:59Z".freeze

    Price = Data.define(:plan, :currency, :amount, :early_bird)

    module_function

    def currencies
      PRICES.keys
    end

    # EARLY_BIRD_UNTIL=off (or empty) switches the early-bird price off.
    def early_bird_until
      value = ENV.fetch("EARLY_BIRD_UNTIL", DEFAULT_EARLY_BIRD_UNTIL)
      return nil if value.blank? || value == "off"

      Time.iso8601(value)
    rescue ArgumentError
      Rails.logger.warn("Ignoring invalid EARLY_BIRD_UNTIL #{value.inspect}")
      nil
    end

    def early_bird?(now = Time.current)
      deadline = early_bird_until
      deadline.present? && now < deadline
    end

    def price_for(currency)
      prices = PRICES.fetch(currency)
      early = early_bird?
      Price.new(plan: PLAN, currency: currency, amount: early ? prices[:early_bird_amount] : prices[:amount], early_bird: early)
    end

    def as_json
      {
        plan:             PLAN,
        prices:           PRICES,
        early_bird_until: early_bird_until&.utc&.iso8601,
        valid_days:       VALID_DAYS
      }
    end
  end
end
