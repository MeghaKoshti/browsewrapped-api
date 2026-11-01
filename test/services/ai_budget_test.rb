require "test_helper"

class AiBudgetTest < ActiveSupport::TestCase
  include BillingHelpers # with_env

  class CountingClassifier
    attr_reader :calls

    def initialize = @calls = []

    def classify(domains)
      @calls << domains
      domains.index_with { { category: "Design", confidence: 0.9 } }
    end
  end

  def entries_for(*domains)
    domains.map { |domain| entry("https://#{domain}/") }
  end

  test "sends domains to the LLM only while today's budget lasts" do
    classifier = CountingClassifier.new

    with_env("AI_DAILY_DOMAIN_BUDGET" => "3") do
      AiDomainCategorizer.new(entries_for("a1.xyz", "a2.xyz"), classifier: classifier).call
      AiDomainCategorizer.new(entries_for("b1.xyz", "b2.xyz"), classifier: classifier).call
      result = AiDomainCategorizer.new(entries_for("c1.xyz"), classifier: classifier).call

      assert_equal [ %w[a1.xyz a2.xyz], %w[b1.xyz] ], classifier.calls
      assert_equal 3, AiBudget.used_today
      assert_empty result.overrides
    end
  end

  test "cached answers are still used once the budget is gone" do
    DomainCategory.create!(domain: "known.xyz", category: "Design", source: "ai")

    with_env("AI_DAILY_DOMAIN_BUDGET" => "0") do
      result = AiDomainCategorizer.new(entries_for("known.xyz", "new.xyz"), classifier: CountingClassifier.new).call

      assert_equal({ "known.xyz" => "Design" }, result.overrides)
    end
  end

  test "logs once when the budget runs out" do
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)

    with_env("AI_DAILY_DOMAIN_BUDGET" => "0") { 3.times { AiBudget.take(5) } }

    assert_equal 1, io.string.scan("AI daily domain budget").size
  ensure
    Rails.logger = original
  end

  test "the budget resets the next UTC day" do
    with_env("AI_DAILY_DOMAIN_BUDGET" => "2") do
      travel_to Time.utc(2026, 12, 1, 23, 0) do
        assert_equal 2, AiBudget.take(5)
        assert_equal 0, AiBudget.take(1)
      end
      travel_to Time.utc(2026, 12, 2, 0, 30) do
        assert_equal 1, AiBudget.take(1)
      end
    end
  end
end
