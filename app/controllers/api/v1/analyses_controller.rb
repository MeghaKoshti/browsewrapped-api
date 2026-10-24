module Api
  module V1
    class AnalysesController < ApplicationController
      SAMPLE_FILE = Rails.root.join("sample/sample_history.json")
      SAMPLE_CACHE_KEY = "sample_report_v2".freeze # bump when the report shape changes
      UNSUPPORTED_MEDIA_TYPE_MESSAGE = "Unsupported file type. Please upload a JSON or CSV export, " \
                                       "or a Firefox, Safari or Chrome history database.".freeze

      # Declared before the upload checks so rejected uploads count too.
      rate_limit to: UPLOAD_RATE_LIMIT, within: RATE_LIMIT_WINDOW, store: rate_limit_store,
                 name: "uploads", only: %i[analyze create]
      before_action :require_valid_upload, only: %i[analyze create]

      # POST /api/v1/analyses
      # Stores the upload and analyses it in the background (202 + id to poll).
      # Files under the sync threshold are analysed inline to keep demos fast (201).
      # The response carries a one-time delete_token for DELETE below.
      def create
        analysis = Analysis.new(source: "upload", filename: upload.original_filename)
        analysis.assign_delete_token
        analysis.save!
        AnalysisUpload.store(analysis.id, upload.tempfile.path)

        if upload.size < self.class.sync_threshold
          AnalyzeHistoryJob.perform_now(analysis.id, sync: true)
          render json: analysis.reload.as_api_json.merge(delete_token: analysis.delete_token), status: :created
        else
          AnalyzeHistoryJob.perform_later(analysis.id)
          render json: analysis.as_api_json.merge(delete_token: analysis.delete_token),
                 status: :accepted, location: api_v1_analysis_url(analysis)
        end
      end

      # DELETE /api/v1/analyses/:id  (header X-Delete-Token)
      # Deletes the report and any upload still waiting for the job, right now.
      def destroy
        analysis = Analysis.find(params[:id])
        unless analysis.deletable_with?(request.headers["X-Delete-Token"])
          return render_error(:invalid_delete_token, "Invalid delete token", :forbidden)
        end

        analysis.purge!
        head :no_content
      end

      # GET /api/v1/analyses/:id
      def show
        render json: Analysis.find(params[:id]).as_api_json
      end

      # POST /api/v1/analyze
      # Original synchronous endpoint, kept for backward compatibility.
      def analyze
        entries = HistoryParser.parse_file(upload.tempfile.path)

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

      # GET /api/v1/chrome
      # Reads the Chrome history of the machine the API runs on, so it is only
      # for running the API on your own computer (LOCAL_CHROME_IMPORT=on).
      def chrome
        unless self.class.local_chrome_import?
          return render_error(:disabled, "Reading local Chrome history is turned off on this server.", :not_found)
        end

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

      # On by default only in development.
      def self.local_chrome_import?
        ENV.fetch("LOCAL_CHROME_IMPORT", Rails.env.development? ? "on" : "off") == "on"
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
        when :sqlite
          require_known_sqlite
        when nil
          render_error :unsupported_media_type, UNSUPPORTED_MEDIA_TYPE_MESSAGE, :unsupported_media_type
        end
      end

      # Opening the database is cheap, so an unknown or broken SQLite file is
      # refused here, before anything is stored or queued.
      def require_known_sqlite
        return if SqliteHistoryReader.detect(upload.tempfile.path)

        render_error :unsupported_sqlite, SqliteHistoryReader::UNKNOWN_MESSAGE, :unsupported_media_type
      rescue SqliteHistoryReader::CorruptDatabaseError => e
        render_error :corrupt_sqlite, e.message, :unprocessable_entity
      end
    end
  end
end
