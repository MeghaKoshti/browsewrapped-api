require "test_helper"

class AiDomainCategorizerTest < ActiveSupport::TestCase
  # Records what it was asked and answers from a fixed table.
  class FakeClassifier
    attr_reader :calls

    def initialize(answers = {}, error: nil)
      @answers = answers
      @error   = error
      @calls   = []
    end

    def classify(domains)
      @calls << domains
      raise @error if @error

      domains.index_with { |d| { category: @answers.fetch(d, "Other"), confidence: 0.9 } }
    end
  end

  def entries
    [
      entry("https://tailwindcss.com/docs/flex", visit_count: 5),
      entry("https://modelcontextprotocol.io/spec", visit_count: 9),
      entry("https://plinkerton.xyz/p", visit_count: 1),
      entry("https://github.com/rails/rails") # already categorised by rules
    ]
  end

  def with_env(values)
    originals = values.keys.index_with { |k| ENV[k] }
    values.each { |k, v| ENV[k] = v }
    yield
  ensure
    originals.each { |k, v| ENV[k] = v }
  end

  test "sends only Other domains, most visited first, in one batch" do
    fake = FakeClassifier.new({ "tailwindcss.com" => "Design", "modelcontextprotocol.io" => "AI & ML" })

    result = AiDomainCategorizer.new(entries, classifier: fake).call

    assert_equal [ %w[modelcontextprotocol.io tailwindcss.com plinkerton.xyz] ], fake.calls
    assert_equal({ "tailwindcss.com" => "Design", "modelcontextprotocol.io" => "AI & ML" }, result.overrides)
    assert_equal 2, result.ai_classified
  end

  test "caches every answer so a domain is never sent twice" do
    AiDomainCategorizer.new(entries, classifier: FakeClassifier.new({ "tailwindcss.com" => "Design" })).call
    second = FakeClassifier.new

    result = AiDomainCategorizer.new(entries, classifier: second).call

    assert_empty second.calls
    assert_equal "Design", result.overrides["tailwindcss.com"]
    assert_equal "Other", DomainCategory.find_by(domain: "plinkerton.xyz").category
  end

  test "manual categories are used and not counted as AI" do
    DomainCategory.create!(domain: "tailwindcss.com", category: "Design", source: "manual")

    result = AiDomainCategorizer.new(entries, classifier: FakeClassifier.new).call

    assert_equal "Design", result.overrides["tailwindcss.com"]
    assert_equal 0, result.ai_classified
  end

  test "caps the number of domains sent" do
    fake = FakeClassifier.new
    with_env("AI_CATEGORISATION_MAX_DOMAINS" => "1") do
      AiDomainCategorizer.new(entries, classifier: fake).call
    end

    assert_equal [ %w[modelcontextprotocol.io] ], fake.calls
  end

  test "falls back to Other when the classifier fails" do
    fake = FakeClassifier.new(error: LlmDomainClassifier::Error.new("timeout"))

    result = AiDomainCategorizer.new(entries, classifier: fake).call

    assert_empty result.overrides
    assert_equal 0, DomainCategory.count
  end

  test "works without an API key" do
    with_env("GEMINI_API_KEY" => nil) do
      assert_equal AiDomainCategorizer::EMPTY, AiDomainCategorizer.new(entries).call
    end
  end

  test "can be switched off" do
    fake = FakeClassifier.new
    with_env("AI_CATEGORISATION" => "off") do
      assert_equal AiDomainCategorizer::EMPTY, AiDomainCategorizer.new(entries, classifier: fake).call
    end
    assert_empty fake.calls
  end

  test "the analyzer applies overrides only to domains the rules left as Other" do
    overrides = { "tailwindcss.com" => "Design", "github.com" => "Shopping" }
    topics = HistoryAnalyzer.new(entries, domain_overrides: overrides).analyze[:top_domains].to_h { |d| [ d[:domain], d[:topic] ] }

    assert_equal "Design", topics["tailwindcss.com"]
    assert_equal "Programming", topics["github.com"]
  end
end
