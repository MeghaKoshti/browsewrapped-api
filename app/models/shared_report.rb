# A read-only, privacy-sanitised copy of a report, reachable at /r/:token.
#
# - token: random and unguessable (never the sequential id)
# - delete token: shown once at creation; only its SHA-256 digest is stored
# - expires after 30 days (CleanupExpiredSharedReportsJob deletes old rows)
class SharedReport < ApplicationRecord
  TTL = 30.days
  MAX_DATA_BYTES = 512.kilobytes

  has_secure_token :token

  scope :active,  -> { where(expires_at: Time.current..) }
  scope :expired, -> { where(expires_at: ...Time.current) }

  validates :delete_token_digest, presence: true
  validate  :data_has_a_summary_and_fits

  before_validation { self.expires_at ||= TTL.from_now }

  attr_reader :delete_token

  # Builds a shared report from a full analysis result. The plain delete token
  # is only available on this instance (#delete_token), never stored.
  def self.build_from_report(report)
    new(data: ReportSanitizer.call(report)).tap(&:assign_delete_token)
  end

  def self.digest(value)
    OpenSSL::Digest::SHA256.hexdigest(value.to_s)
  end

  def assign_delete_token
    @delete_token = SecureRandom.base58(32)
    self.delete_token_digest = self.class.digest(@delete_token)
  end

  def deletable_with?(candidate)
    candidate.present? && ActiveSupport::SecurityUtils.secure_compare(self.class.digest(candidate), delete_token_digest)
  end

  def expired?
    expires_at.past?
  end

  private

  def data_has_a_summary_and_fits
    errors.add(:data, "must be a report with a summary") unless data.is_a?(Hash) && data["summary"].is_a?(Hash)
    errors.add(:data, "is too large to share") if data.to_json.bytesize > MAX_DATA_BYTES
  end
end
