class ApplicationController < ActionController::API
  include ApiErrors
  include Entitlements

  # Per-IP limits for the expensive or abuse-prone endpoints (see `rate_limit`
  # in the controllers). Counters live in Rails.cache (Solid Cache in
  # production, so every Puma worker shares them).
  RATE_LIMIT_WINDOW = 1.minute
  UPLOAD_RATE_LIMIT = ENV.fetch("UPLOAD_RATE_LIMIT_PER_MINUTE", 10).to_i
  SHARE_RATE_LIMIT  = ENV.fetch("SHARE_RATE_LIMIT_PER_MINUTE", 20).to_i
  CHECKOUT_RATE_LIMIT = ENV.fetch("CHECKOUT_RATE_LIMIT_PER_MINUTE", 10).to_i
  MAGIC_LINK_IP_RATE_LIMIT = ENV.fetch("MAGIC_LINK_RATE_LIMIT_PER_MINUTE", 5).to_i
  MAGIC_LINK_EMAIL_RATE_LIMIT = ENV.fetch("MAGIC_LINK_EMAIL_LIMIT_PER_HOUR", 5).to_i

  # Tests set their own store. An unset config.x key is an empty (but truthy)
  # OrderedOptions, hence presence rather than ||.
  def self.rate_limit_store
    Rails.configuration.x.rate_limit_store.presence || Rails.cache
  end
end
