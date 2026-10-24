require "test_helper"

class LlmDomainClassifierTest < ActiveSupport::TestCase
  def classifier_returning(text, &on_prompt)
    LlmDomainClassifier.new(transport: ->(prompt) { on_prompt&.call(prompt); text })
  end

  test "maps each domain to a validated category and confidence" do
    json = '[{"domain":"tailwindcss.com","category":"Design","confidence":0.92},
             {"domain":"amazon.in","category":"Shopping","confidence":1.7}]'

    result = classifier_returning(json).classify(%w[tailwindcss.com amazon.in])

    assert_equal({ category: "Design", confidence: 0.92 }, result["tailwindcss.com"])
    assert_equal({ category: "Shopping", confidence: 1.0 }, result["amazon.in"])
  end

  test "unknown categories and missing domains become Other" do
    json = '[{"domain":"weird.site","category":"Astrology","confidence":0.8}]'

    result = classifier_returning(json).classify(%w[weird.site missing.site])

    assert_equal "Other", result["weird.site"][:category]
    assert_equal "Other", result["missing.site"][:category]
  end

  test "ignores answers for domains that were not asked about" do
    json = '[{"domain":"injected.com","category":"News","confidence":1}]'

    assert_equal %w[asked.com], classifier_returning(json).classify(%w[asked.com]).keys
  end

  test "sends only domain names in the prompt" do
    sent = nil
    classifier_returning("[]") { |prompt| sent = prompt }.classify(%w[example.dev])

    assert_includes sent, "example.dev"
    assert_no_match(%r{https?://}, sent)
  end

  test "raises a classifier error for invalid JSON" do
    assert_raises(LlmDomainClassifier::Error) { classifier_returning("not json").classify(%w[a.com]) }
  end

  test "is only available with an API key" do
    original = ENV.delete("GEMINI_API_KEY")
    assert_not LlmDomainClassifier.available?
  ensure
    ENV["GEMINI_API_KEY"] = original
  end

  test "switches thinking off and defaults to Flash-Lite" do
    original = ENV.delete("GEMINI_MODEL")
    classifier = LlmDomainClassifier.new(api_key: "k")

    body = classifier.request_body("hi")

    assert_equal({ thinkingBudget: 0 }, body.dig(:generationConfig, :thinkingConfig))
    assert_equal "gemini-2.5-flash-lite", classifier.model
  ensure
    ENV["GEMINI_MODEL"] = original
  end

  test "a time budget caps connect plus read time" do
    classifier = LlmDomainClassifier.new(api_key: "k", time_budget: 5)

    assert_operator classifier.open_timeout + classifier.read_timeout, :<=, 5
    assert_operator classifier.read_timeout, :>, 0
  end

  test "without a budget the background timeouts apply" do
    classifier = LlmDomainClassifier.new(api_key: "k")

    assert_equal [ 5, 20 ], [ classifier.open_timeout, classifier.read_timeout ]
  end
end
