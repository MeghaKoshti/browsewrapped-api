class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM", "BrowseWrapped <hello@browsewrapped.local>") }
  layout "mailer"
end
