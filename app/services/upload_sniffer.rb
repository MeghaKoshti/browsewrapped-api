# Looks at the first bytes of an upload to decide whether it can be a history
# export at all, so images, PDFs or zips are rejected up front.
# The file name and Content-Type are ignored: the client chooses both.
module UploadSniffer
  HEAD_BYTES = 4096
  UTF8_BOM   = "\xEF\xBB\xBF".b
  # Control characters that never appear in JSON or CSV text (tab, LF and CR are fine).
  BINARY_BYTES = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/n

  module_function

  # Returns :json, :csv, :sqlite, :empty, or nil when the content is none of them.
  # :sqlite only means "a SQLite file"; SqliteHistoryReader.detect says which browser.
  def detect(path)
    head = File.binread(path, HEAD_BYTES).to_s
    return :sqlite if head.start_with?(SqliteHistoryReader::HEADER)

    head = head.delete_prefix(UTF8_BOM)
    text = head.lstrip

    return :empty if text.empty? && File.size(path) <= HEAD_BYTES
    return nil if BINARY_BYTES.match?(head)
    return :json if text.start_with?("{", "[")
    return :csv if text.lines.first.include?(",")

    nil
  end
end
