module Api
  module V1
    class MeController < ApplicationController
      before_action :require_session!

      # GET /api/v1/me  (Authorization: Bearer <access_token>)
      def show
        render json: { email: current_email, pass_valid_until: pass_valid_until&.iso8601, has_pass: pass? }
      end
    end
  end
end
