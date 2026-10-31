# The one place that decides what counts as an email address. Deliberately
# loose (something@something.tld): the magic link proves the address works.
module EmailAddress
  FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
  MAX_LENGTH = 254

  module_function

  def normalize(value)
    value.to_s.strip.downcase
  end

  def valid?(value)
    email = normalize(value)
    email.length <= MAX_LENGTH && FORMAT.match?(email)
  end
end
