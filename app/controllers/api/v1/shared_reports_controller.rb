module Api
  module V1
    # Public share links for reports (/r/:token in the web app).
    class SharedReportsController < ApplicationController
      rate_limit to: SHARE_RATE_LIMIT, within: RATE_LIMIT_WINDOW, store: rate_limit_store,
                 name: "shares", only: :create
      before_action :find_shared_report, only: %i[show destroy card]

      # POST /api/v1/shared_reports
      # Body: { analysis_id } for a stored analysis, or { report } for a report
      # the client already has (sample data, Chrome import). As JSON, or as
      # multipart form data with an optional `card` (the 1200×630 persona PNG
      # for link previews) and `report` as a JSON string.
      def create
        report = source_report
        return render_error(:nothing_to_share, "Nothing to share", :unprocessable_entity) if report.blank?

        card_png = ShareCard.read_upload(params[:card]) if params[:card].respond_to?(:read)
        shared = SharedReport.build_from_report(report)
        shared.build_card(png: card_png) if card_png

        if shared.save
          render json: {
            token:        shared.token,
            path:         "/r/#{shared.token}",
            preview_url:  AppUrls.api("/s/#{shared.token}"),
            expires_at:   shared.expires_at.iso8601,
            delete_token: shared.delete_token # returned once, never again
          }, status: :created
        else
          render_error :invalid_report, shared.errors.full_messages.to_sentence, :unprocessable_entity
        end
      rescue ShareCard::Rejected => e
        render_error e.code, e.message, e.status
      end

      # GET /api/v1/shared_reports/:token
      def show
        render json: {
          token:      @shared_report.token,
          report:     @shared_report.data,
          created_at: @shared_report.created_at.iso8601,
          expires_at: @shared_report.expires_at.iso8601
        }
      end

      # GET /api/v1/shared_reports/:token/card.png
      def card
        png = @shared_report.card&.png
        return render_error(:not_found, "This shared report has no card image", :not_found) unless png

        expires_in 1.hour, public: true
        send_data png, type: "image/png", disposition: "inline", filename: "browsewrapped-#{@shared_report.token}.png"
      end

      # DELETE /api/v1/shared_reports/:token  (header X-Delete-Token)
      def destroy
        unless @shared_report.deletable_with?(request.headers["X-Delete-Token"] || params[:delete_token])
          return render_error(:invalid_delete_token, "Invalid delete token", :forbidden)
        end

        @shared_report.destroy!
        head :no_content
      end

      private

      def find_shared_report
        @shared_report = SharedReport.active.find_by(token: params[:token].to_s)
        render_error :not_found, "This shared report doesn't exist or has expired", :not_found unless @shared_report
      end

      def source_report
        if params[:analysis_id].present?
          Analysis.completed.find_by(id: params[:analysis_id])&.result
        elsif params[:report].respond_to?(:to_unsafe_h)
          # Only allowlisted sections survive ReportSanitizer, so permitting all here is safe.
          params[:report].to_unsafe_h
        elsif params[:report].is_a?(String)
          parse_report_string(params[:report])
        end
      end

      # A multipart form sends the report as a JSON string.
      def parse_report_string(json)
        report = JSON.parse(json)
        report if report.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
