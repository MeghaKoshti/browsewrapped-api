module Api
  module V1
    # Passwordless sign-in for Pass holders: an emailed single-use link.
    class SessionsController < ApplicationController
      ACCEPTED = { message: "If that address can sign in, a link is on its way. It expires in 15 minutes." }.freeze

      # Per IP: a normal 429. Per email: the same 202 as always, with no email
      # sent, so the response never tells an attacker anything about an address.
      rate_limit to: MAGIC_LINK_IP_RATE_LIMIT, within: RATE_LIMIT_WINDOW, store: rate_limit_store,
                 name: "magic_link_ip", only: :magic_link
      rate_limit to: MAGIC_LINK_EMAIL_RATE_LIMIT, within: 1.hour, store: rate_limit_store,
                 name: "magic_link_email", only: :magic_link,
                 by: -> { EmailAddress.normalize(params[:email]) }, with: -> { render json: ACCEPTED, status: :accepted }
      rate_limit to: 20, within: RATE_LIMIT_WINDOW, store: rate_limit_store, name: "verify", only: :verify

      # POST /api/v1/sessions/magic_link  { email }  => always 202
      # A link is sent to any valid address, Pass or not: the success page asks
      # for one right after paying, possibly before the payment webhook lands,
      # and the web app then polls /me until has_pass turns true.
      def magic_link
        email = EmailAddress.normalize(params[:email])
        send_link(email) if EmailAddress.valid?(email)

        render json: ACCEPTED, status: :accepted
      end

      # POST /api/v1/sessions/verify  { token }
      # POST rather than GET so the token never lands in access logs.
      def verify
        email = MagicLinkToken.redeem(params[:token].to_s)
        return render_error(:invalid_or_expired_token, "This sign-in link is invalid or has expired. Please ask for a new one.", :unauthorized) unless email

        render json: {
          access_token:     PassSession.issue(email),
          email:            email,
          pass_valid_until: Purchase.pass_valid_until(email)&.iso8601
        }
      end

      private

      # Sent inline, not with deliver_later: a queued job would keep the plain
      # token in its arguments (job logs and the Solid Queue tables).
      def send_link(email)
        link = MagicLinkToken.issue!(email)
        PassMailer.magic_link(email: email, token: link.token).deliver_now
      rescue StandardError => e
        Rails.logger.error("Magic link email failed: #{e.class}: #{e.message}")
      end
    end
  end
end
