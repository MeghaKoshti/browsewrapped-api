module Api
  module V1
    class CheckoutsController < ApplicationController
      rate_limit to: CHECKOUT_RATE_LIMIT, within: RATE_LIMIT_WINDOW, store: rate_limit_store, name: "checkouts"

      # POST /api/v1/checkouts  { email, currency: "INR" | "USD", plan: "wrapped_pass" (optional) }
      # => 201 { checkout_url }. The price comes from Billing::Pricing, never from the client.
      def create
        email = EmailAddress.normalize(params[:email])
        currency = params[:currency].to_s.upcase

        return render_error(:invalid_email, "Please enter a valid email address.", :unprocessable_entity) unless EmailAddress.valid?(email)
        return render_error(:invalid_currency, "Currency must be INR or USD.", :unprocessable_entity) unless Billing::Pricing.currencies.include?(currency)
        if params[:plan].present? && params[:plan] != Billing::Pricing::PLAN
          return render_error(:invalid_plan, "Unknown plan.", :unprocessable_entity)
        end

        price = Billing::Pricing.price_for(currency)
        checkout = Billing.provider.create_checkout(
          email:       email,
          price:       price,
          success_url: AppUrls.web("/billing/success"),
          cancel_url:  AppUrls.web("/billing/cancel"),
          metadata:    { plan: price.plan, email: email }
        )

        render json: { checkout_url: checkout.url }, status: :created
      rescue Billing::Error => e
        Rails.logger.error("Checkout failed: #{e.class}: #{e.message}")
        render_error :checkout_unavailable, "Checkout is unavailable right now. Please try again in a few minutes.", :service_unavailable
      end
    end
  end
end
