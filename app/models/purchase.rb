# One paid Wrapped Pass. Paying again while a Pass is active extends it: the
# new purchase starts when the current one ends. A refund revokes it.
class Purchase < ApplicationRecord
  normalizes :email, with: ->(email) { EmailAddress.normalize(email) }

  validates :email, :plan, :currency, :provider, :provider_ref, :valid_until, presence: true
  validates :amount, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :provider_ref, uniqueness: { scope: :provider }

  scope :active, -> { where(revoked_at: nil, valid_until: Time.current..) }

  # The end of the email's Pass, or nil without an active one.
  def self.pass_valid_until(email)
    active.where(email: EmailAddress.normalize(email)).maximum(:valid_until)
  end

  # Idempotent per provider payment id.
  def self.record_payment!(email:, plan:, amount:, currency:, provider:, provider_ref:)
    find_by(provider: provider, provider_ref: provider_ref) || begin
      starts = [ pass_valid_until(email), Time.current ].compact.max
      create!(email: email, plan: plan, amount: amount.to_i, currency: currency.to_s.upcase,
              provider: provider, provider_ref: provider_ref,
              valid_until: starts + Billing::Pricing::VALID_DAYS.days)
    end
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current) unless revoked?
  end
end
