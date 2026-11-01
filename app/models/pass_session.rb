# The bearer token a signed-in Pass holder sends as "Authorization: Bearer ...".
# It is a signed (not encrypted) message holding only the email, valid 30
# days. There is no server-side session to look up; the Pass itself is checked
# against purchases on every request, so a refund takes effect at once.
module PassSession
  TTL = 30.days
  PURPOSE = :pass_session

  module_function

  def issue(email)
    verifier.generate({ "email" => EmailAddress.normalize(email) }, expires_in: TTL, purpose: PURPOSE)
  end

  # => the email, or nil for a missing, forged or expired token.
  def email_for(token)
    return nil if token.blank?

    verifier.verified(token, purpose: PURPOSE)&.fetch("email", nil)
  end

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
