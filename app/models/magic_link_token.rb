# A single-use sign-in link, valid for 15 minutes. The plain token only
# exists in the email (and in memory right after .issue); the database holds
# its SHA-256 digest, so a leaked table can't be used to sign in.
class MagicLinkToken < ApplicationRecord
  TTL = 15.minutes

  normalizes :email, with: ->(email) { EmailAddress.normalize(email) }

  scope :expired, -> { where(expires_at: ...Time.current) }

  attr_reader :token

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  end

  def self.issue!(email)
    token = SecureRandom.base58(32)
    create!(email: email, token_digest: digest(token), expires_at: TTL.from_now).tap { |row| row.instance_variable_set(:@token, token) }
  end

  # Marks the token used and returns its email, or nil if the token is
  # unknown, expired or already used. The conditional UPDATE makes two
  # simultaneous redemptions impossible.
  def self.redeem(token)
    return nil if token.blank?

    row = find_by(token_digest: digest(token))
    return nil unless row

    used = where(id: row.id, used_at: nil, expires_at: Time.current..).update_all(used_at: Time.current, updated_at: Time.current)
    row.email if used == 1
  end
end
