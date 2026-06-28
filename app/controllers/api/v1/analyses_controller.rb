module Api
  module V1
    class AnalysesController < ApplicationController
      MAX_FILE_SIZE = 100.megabytes

      def create
        file = params[:file]
        return render json: { error: "No file provided" }, status: :unprocessable_entity unless file

        if file.size > MAX_FILE_SIZE
          return render json: { error: "File too large (max 100 MB)" }, status: :unprocessable_entity
        end

        content = file.read
        entries = HistoryParser.parse(content)

        if entries.empty?
          return render json: { error: "No valid browser history entries found in the file" }, status: :unprocessable_entity
        end

        result = HistoryAnalyzer.new(entries).analyze
        result[:meta] = { total_entries_parsed: entries.size, source: "upload", processed_at: Time.current.iso8601 }

        render json: result
      rescue => e
        Rails.logger.error("Analysis error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def chrome
        unless ChromeHistoryReader.available?
          return render json: { error: "Chrome history not found on this machine." }, status: :not_found
        end

        entries = ChromeHistoryReader.read

        result = HistoryAnalyzer.new(entries).analyze
        result[:meta] = { total_entries_parsed: entries.size, source: "chrome_direct", processed_at: Time.current.iso8601 }

        render json: result
      rescue => e
        Rails.logger.error("Chrome read error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end
