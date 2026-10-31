require "net/http"

# Dodo Payments (merchant of record; accepts Indian individuals, UPI and cards).
#
# Checkout: POST /checkouts creates a hosted checkout session for one-time
# products and returns { session_id, checkout_url }.
#   https://docs.dodopayments.com/developer-resources/checkout-session
# Base URLs: https://test.dodopayments.com (test mode), https://live.dodopayments.com
# (live mode), with "Authorization: Bearer <API key>".
#   https://docs.dodopayments.com/api-reference/introduction
# Webhooks: Standard Webhooks signatures, events payment.succeeded and
# refund.succeeded (among others).
#   https://docs.dodopayments.com/developer-resources/webhooks
#   https://docs.dodopayments.com/developer-resources/webhooks/intents/webhook-events-guide
#
# HTTP goes through an injectable transport, so tests never touch the network:
#   transport.call(uri, headers, json_body) # => [status_code, response_body]
module Billing
  class DodoProvider < Provider
    BASE_URLS = { "test_mode" => "https://test.dodopayments.com", "live_mode" => "https://live.dodopayments.com" }.freeze
    TIMEOUT = 10

    def initialize(env: ENV, transport: nil)
      @env       = env
      @transport = transport || method(:http_post)
    end

    def create_checkout(email:, price:, success_url:, cancel_url:, metadata: {})
      body = {
        product_cart: [ { product_id: product_id_for(price.currency), quantity: 1 } ],
        customer:     { email: email },
        # Dodo appends payment_id, status and email to the return URL.
        return_url:   success_url,
        cancel_url:   cancel_url,
        metadata:     metadata.transform_values(&:to_s)
      }
      body[:discount_codes] = [ early_bird_code ] if price.early_bird

      status, response = @transport.call(URI("#{base_url}/checkouts"), request_headers, JSON.generate(body))
      raise CheckoutError, "Dodo checkout failed with HTTP #{status}" unless status.to_i.between?(200, 299)

      json = JSON.parse(response)
      raise CheckoutError, "Dodo returned no checkout_url" if json["checkout_url"].blank?

      Checkout.new(id: json["session_id"], url: json["checkout_url"])
    rescue JSON::ParserError
      raise CheckoutError, "Dodo returned invalid JSON"
    end

    def parse_event(body)
      DodoPayload.parse(body, product_ids: Pricing.currencies.map { |currency| @env["DODO_PRODUCT_PASS_#{currency}"] })
    end

    private

    def webhook_secret
      @env["DODO_WEBHOOK_SECRET"]
    end

    def base_url
      BASE_URLS.fetch(@env.fetch("DODO_ENVIRONMENT", "test_mode")) do |mode|
        raise ConfigError, "DODO_ENVIRONMENT must be test_mode or live_mode, not #{mode.inspect}"
      end
    end

    def request_headers
      api_key = @env["DODO_API_KEY"].presence || raise(ConfigError, "DODO_API_KEY is not set")
      { "Authorization" => "Bearer #{api_key}", "Content-Type" => "application/json" }
    end

    def product_id_for(currency)
      @env["DODO_PRODUCT_PASS_#{currency}"].presence || raise(ConfigError, "DODO_PRODUCT_PASS_#{currency} is not set")
    end

    # A Dodo product has one price, so the early-bird price is a discount code
    # set up in the dashboard. Refuse to sell rather than charge more than the
    # pricing page shows.
    def early_bird_code
      @env["DODO_EARLY_BIRD_DISCOUNT_CODE"].presence ||
        raise(ConfigError, "DODO_EARLY_BIRD_DISCOUNT_CODE is not set but the early-bird price is on")
    end

    def http_post(uri, headers, body)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.post(uri.request_uri, body, headers)
      end
      [ response.code.to_i, response.body ]
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
      raise CheckoutError, "Dodo request failed: #{e.class}"
    end
  end
end
