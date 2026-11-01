class PassMailer < ApplicationMailer
  # The link opens the web app, which posts the token to /api/v1/sessions/verify.
  def magic_link(email:, token:)
    @url = AppUrls.web("/auth/verify?#{{ token: token }.to_query}")
    @valid_minutes = (MagicLinkToken::TTL / 1.minute).to_i
    mail to: email, subject: "Your BrowseWrapped sign-in link"
  end
end
