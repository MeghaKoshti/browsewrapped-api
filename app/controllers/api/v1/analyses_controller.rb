module Api
  module V1
    class AnalysesController < ApplicationController
      SAMPLE_FILE = Rails.root.join("sample/sample_history.json")
      SAMPLE_CACHE_KEY = "sample_report_v2".freeze # bump when the report shape changes

      # Declared before the upload checks so rejected uploads count too.
      rate_limit to: UPLOAD_RATE_LIMIT, within: RATE_LIMIT_WINDOW, store: rate_limit_store,
                 name: "uploads", only: %i[analyze create]
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
        render json: Analysis.find(params[:id]).as_api_json
      end

      # POST /api/v1/analyze
      # Original synchronous endpoint, kept for backward compatibility.
      def analyze
        entries = HistoryParser.parse(upload.read)

        if entries.empty?
          return render_error(:no_entries, AnalyzeHistoryJob::NO_ENTRIES_MESSAGE, :unprocessable_entity)
        end

        result = HistoryAnalyzer.new(entries).analyze
        result[:meta] = { total_entries_parsed: entries.size, source: "upload", processed_at: Time.current.iso8601 }

        render json: result
      rescue HistoryParser::UnsupportedFormatError => e
        render_error :unsupported_format, e.message, :unprocessable_entity
      rescue => e
        Rails.logger.error("Analysis error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        render_error :analysis_failed, "Something went wrong while analysing your history. Please try again.", :unprocessable_entity
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
          return render_error(:not_found, "Chrome history not found on this machine.", :not_found)
        end

        chrome_data = ChromeHistoryReader.read
        entries  = chrome_data[:entries]
        searches = chrome_data[:searches]

        result = HistoryAnalyzer.new(entries, chrome_searches: searches).analyze
        result[:meta] = { total_entries_parsed: entries.size, source: "chrome_direct", processed_at: Time.current.iso8601 }

        render json: result
      rescue => e
        Rails.logger.error("Chrome read error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        render_error :chrome_read_failed, e.message, :unprocessable_entity
      end

      # Uploads smaller than this many bytes are analysed synchronously.
      def self.sync_threshold
        ENV.fetch("ANALYSIS_SYNC_THRESHOLD_BYTES", 5.megabytes).to_i
      end

      def self.max_upload_bytes
        ENV.fetch("ANALYSIS_MAX_UPLOAD_BYTES", 100.megabytes).to_i
      end

      private

      def upload
        params[:file]
      end

      def require_valid_upload
        unless upload.respond_to?(:tempfile)
          return render_error(:missing_file, "No file provided", :unprocessable_entity)
        end

        max = self.class.max_upload_bytes
        if upload.size > max
          return render_error(:payload_too_large, "File too large (max #{ActiveSupport::NumberHelper.number_to_human_size(max)})", :content_too_large)
        end

        case UploadSniffer.detect(upload.tempfile.path)
        when :empty
          render_error :empty_file, "The file is empty", :unprocessable_entity
        when nil
          render_error :unsupported_media_type, "Unsupported file type. Please upload a JSON or CSV history export.", :unsupported_media_type
        end
      end
    end
  end
end
