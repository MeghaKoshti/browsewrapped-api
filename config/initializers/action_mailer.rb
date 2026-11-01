# Mail jobs carry recipients and links in their arguments; keep them out of
# the logs (personal data, and sign-in tokens if a mailer were ever queued).
ActiveSupport.on_load(:action_mailer) do
  ActionMailer::MailDeliveryJob.log_arguments = false
end
