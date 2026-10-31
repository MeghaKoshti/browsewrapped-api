# Preview at http://localhost:3000/rails/mailers/pass_mailer/magic_link
class PassMailerPreview < ActionMailer::Preview
  def magic_link
    PassMailer.magic_link(email: "buyer@example.com", token: "preview-token-not-valid")
  end
end
