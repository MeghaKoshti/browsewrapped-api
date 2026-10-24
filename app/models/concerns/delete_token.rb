# A one-time "delete token" for anonymous owners: the plain token is shown once
# (right after create) and only its SHA-256 digest is stored, so a database
# leak can't be used to delete other people's data.
module DeleteToken
  extend ActiveSupport::Concern

  included do
    attr_reader :delete_token
  end

  class_methods do
    def digest(value)
      OpenSSL::Digest::SHA256.hexdigest(value.to_s)
    end
  end

  def assign_delete_token
    @delete_token = SecureRandom.base58(32)
    self.delete_token_digest = self.class.digest(@delete_token)
  end

  def deletable_with?(candidate)
    candidate.present? && delete_token_digest.present? &&
      ActiveSupport::SecurityUtils.secure_compare(self.class.digest(candidate), delete_token_digest)
  end
end
