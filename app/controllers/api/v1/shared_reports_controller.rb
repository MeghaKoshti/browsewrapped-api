module Api
  module V1
    # Public share links for reports (/r/:token in the web app).
    class SharedReportsController < ApplicationController
      before_action :find_shared_report, only: %i[show destroy]

      # POST /api/v1/shared_reports
      # Body: { analysis_id } for a stored analysis, or { report } for a report
      # the client already has (sample data, Chrome import).
      def create
        report = source_report
        return render json: { error: "Nothing to share" }, status: :unprocessable_entity if report.blank?

        shared = SharedReport.build_from_report(report)
        if shared.save
          render json: {
            token:        shared.token,
            path:         "/r/#{shared.token}",
            expires_at:   shared.expires_at.iso8601,
            delete_token: shared.delete_token # returned once, never again
          }, status: :created
        else
          render json: { error: shared.errors.full_messages.to_sentence }, status: :unprocessable_entity
        end
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

      # DELETE /api/v1/shared_reports/:token  (header X-Delete-Token)
      def destroy
        unless @shared_report.deletable_with?(request.headers["X-Delete-Token"] || params[:delete_token])
          return render json: { error: "Invalid delete token" }, status: :forbidden
        end

        @shared_report.destroy!
        head :no_content
      end

      private

      def find_shared_report
        @shared_report = SharedReport.active.find_by(token: params[:token].to_s)
        render json: { error: "This shared report doesn't exist or has expired" }, status: :not_found unless @shared_report
      end

      def source_report
        if params[:analysis_id].present?
          Analysis.completed.find_by(id: params[:analysis_id])&.result
        elsif params[:report].respond_to?(:to_unsafe_h)
          # Only allowlisted sections survive ReportSanitizer, so permitting all here is safe.
          params[:report].to_unsafe_h
        end
      end
    end
  end
end
