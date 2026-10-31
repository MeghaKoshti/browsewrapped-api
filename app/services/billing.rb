# Selling the one-time Wrapped Pass through a payment provider.
#
#   Billing.provider  # => Billing::FakeProvider (development/test) or Billing::DodoProvider
#
# Every provider implements the Billing::Provider interface, so switching to
# another merchant of record (e.g. Polar) is one new adapter.
module Billing
  class Error < StandardError; end
  # The provider is misconfigured (missing keys, fake provider in production).
  class ConfigError < Error; end

  PROVIDERS = { "fake" => "Billing::FakeProvider", "dodo" => "Billing::DodoProvider" }.freeze

  module_function

  def provider_name
    ENV.fetch("BILLING_PROVIDER", Rails.env.production? ? "dodo" : "fake")
  end

  def provider
    klass = PROVIDERS[provider_name]&.constantize
    raise ConfigError, "Unknown BILLING_PROVIDER #{provider_name.inspect}" unless klass
    raise ConfigError, "The fake billing provider is not available in production" if klass == FakeProvider && !FakeProvider.enabled?

    klass.new
  end
end
