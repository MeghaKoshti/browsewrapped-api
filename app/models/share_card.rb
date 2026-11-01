# The 1200×630 persona card a shared report shows in link previews
# (WhatsApp, X, LinkedIn, Slack). Only real PNGs of the right size are kept.
class ShareCard < ApplicationRecord
  PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b.freeze
  MAX_BYTES = 300.kilobytes
  WIDTH  = 1200
  HEIGHT = 630

  # Why an upload was refused, with the HTTP status to answer.
  class Rejected < StandardError
    attr_reader :code, :status

    def initialize(code, status, message)
      @code, @status = code, status
      super(message)
    end
  end

  belongs_to :shared_report

  # Reads and checks an uploaded file; returns the PNG bytes or raises Rejected.
  def self.read_upload(upload)
    raise Rejected.new(:payload_too_large, :content_too_large, "The card image must be 300 KB or smaller.") if upload.size > MAX_BYTES

    bytes = upload.read.b
    raise Rejected.new(:unsupported_media_type, :unsupported_media_type, "The card image must be a PNG.") unless png?(bytes)

    unless dimensions(bytes) == [ WIDTH, HEIGHT ]
      raise Rejected.new(:invalid_card_dimensions, :unprocessable_entity, "The card image must be #{WIDTH}×#{HEIGHT} pixels.")
    end

    bytes
  end

  # Magic bytes, then an IHDR chunk; the file extension and Content-Type are ignored.
  def self.png?(bytes)
    bytes.start_with?(PNG_SIGNATURE) && bytes.byteslice(12, 4) == "IHDR"
  end

  # Width and height from the IHDR chunk (two big-endian 32-bit integers).
  def self.dimensions(bytes)
    bytes.byteslice(16, 8)&.unpack("NN")
  end
end
