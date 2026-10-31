module Api
  module V1
    class PricingController < ApplicationController
      # GET /api/v1/pricing
      def show
        render json: Billing::Pricing.as_json
      end
    end
  end
end
