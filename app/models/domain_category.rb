# Per-domain category cache. Rows come from the LLM (source "ai") or are set by
# hand (source "manual", which always wins). A domain is never sent to the LLM
# twice: even "Other" answers are cached.
class DomainCategory < ApplicationRecord
  SOURCES = %w[ai manual].freeze

  validates :domain, presence: true, uniqueness: true
  validates :category, inclusion: { in: ->(_) { UrlCategorizer::CATEGORY_COLORS.keys } }
  validates :source, inclusion: { in: SOURCES }
  validates :confidence, numericality: { in: 0..1 }, allow_nil: true

  before_validation { self.domain = domain.to_s.downcase.strip.delete_prefix("www.") }
end
