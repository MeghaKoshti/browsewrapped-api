module Api
  module V1
    class AnalysesController < ApplicationController
      MAX_FILE_SIZE = 100.megabytes
      SAMPLE_FILE = Rails.root.join("sample/sample_history.json")
      SAMPLE_CACHE_KEY = "sample_report_v1".freeze

      before_action :require_valid_upload, only: %i[analyze create]

      # POST /api/v1/analyses
      # Stores the upload and analyses it in the background (202 + id to poll).
      # Files under the sync threshold are analysed inline to keep demos fast (201).
      def create
        analysis = Analysis.create!(source: "upload", filename: upload.original_filename)
        AnalysisUpload.store(analysis.id, upload.tempfile.path)

        if upload.size < self.class.sync_threshold
          AnalyzeHistoryJob.perform_now(analysis.id)
          render json: analysis.reload.as_api_json, status: :created
        else
          AnalyzeHistoryJob.perform_later(analysis.id)
          render json: analysis.as_api_json, status: :accepted, location: api_v1_analysis_url(analysis)
        end
      end

      # GET /api/v1/analyses/:id
      def show
        analysis = Analysis.find_by(id: params[:id])
        return render json: { error: "Analysis not found" }, status: :not_found unless analysis

        render json: analysis.as_api_json
      end

      # POST /api/v1/analyze
      # Original synchronous endpoint, kept for backward compatibility.
      def analyze
        entries = HistoryParser.parse(upload.read)

        if entries.empty?
          return render json: { error: AnalyzeHistoryJob::NO_ENTRIES_MESSAGE }, status: :unprocessable_entity
        end

        result = HistoryAnalyzer.new(entries).analyze
        result[:meta] = { total_entries_parsed: entries.size, source: "upload", processed_at: Time.current.iso8601 }

        render json: result
      rescue => e
        Rails.logger.error("Analysis error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # GET /api/v1/sample
      # Analyses the bundled synthetic sample file so visitors can try the app
      # without exporting their own history. Cached because the input never changes.
      def sample
        result = Rails.cache.fetch(SAMPLE_CACHE_KEY, expires_in: 1.day) do
          entries = HistoryParser.parse(File.read(SAMPLE_FILE))
          report  = HistoryAnalyzer.new(entries).analyze
          report[:meta] = { total_entries_parsed: entries.size, source: "sample", processed_at: Time.current.iso8601 }
          report
        end

        render json: result
      end

      def chrome
        unless ChromeHistoryReader.available?
          return render json: { error: "Chrome history not found on this machine." }, status: :not_found
        end

        chrome_data = ChromeHistoryReader.read
        entries  = chrome_data[:entries]
        searches = chrome_data[:searches]

        result = HistoryAnalyzer.new(entries, chrome_searches: searches).analyze
        result[:meta] = { total_entries_parsed: entries.size, source: "chrome_direct", processed_at: Time.current.iso8601 }

        render json: result
      rescue => e
        Rails.logger.error("Chrome read error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # Uploads smaller than this many bytes are analysed synchronously.
      def self.sync_threshold
        ENV.fetch("ANALYSIS_SYNC_THRESHOLD_BYTES", 5.megabytes).to_i
      end

      private

      def upload
        params[:file]
      end

      def require_valid_upload
        unless upload.respond_to?(:tempfile)
          return render json: { error: "No file provided" }, status: :unprocessable_entity
        end

        if upload.size > MAX_FILE_SIZE
          render json: { error: "File too large (max 100 MB)" }, status: :unprocessable_entity
        end
      end
    end
  end
end
