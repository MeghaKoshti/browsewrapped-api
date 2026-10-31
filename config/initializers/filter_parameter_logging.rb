# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
#
# `report` is a whole browsing report (top pages, searches) posted by the web app
# for sample/Chrome shares; it must never reach the logs before ReportSanitizer runs.
# `customer` is the buyer's details inside payment webhooks.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :report, :customer
]
