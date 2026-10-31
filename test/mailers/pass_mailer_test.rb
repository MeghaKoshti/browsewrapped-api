require "test_helper"

class PassMailerTest < ActionMailer::TestCase
  test "magic link email has HTML and text parts with the web link" do
    mail = PassMailer.magic_link(email: "a@b.co", token: "abc123")

    assert_equal [ "a@b.co" ], mail.to
    assert_equal "Your BrowseWrapped sign-in link", mail.subject
    assert_equal %w[text/plain text/html], mail.parts.map(&:mime_type)
    assert_includes mail.text_part.body.to_s, "http://localhost:5173/auth/verify?token=abc123"
    assert_includes mail.html_part.body.to_s, "http://localhost:5173/auth/verify?token=abc123"
    assert_includes mail.text_part.body.to_s, "expires in 15 minutes"
  end
end
