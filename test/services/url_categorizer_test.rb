require "test_helper"

class UrlCategorizerTest < ActiveSupport::TestCase
  setup { @categorizer = UrlCategorizer.new }

  test "maps known domains to their topic" do
    assert_equal "Programming", @categorizer.categorize("https://github.com/rails/rails")
    assert_equal "AI & ML", @categorizer.categorize("https://huggingface.co/models")
    assert_equal "Design", @categorizer.categorize("https://www.figma.com/file/abc")
  end

  test "ignores the www prefix and letter case" do
    assert_equal "Programming", @categorizer.categorize("https://WWW.StackOverflow.com/questions")
  end

  test "matches subdomains of known domains" do
    assert_equal "Programming", @categorizer.categorize("https://gist.github.com/someone/123")
  end

  test "falls back to keywords for unknown domains" do
    assert_equal "Programming", @categorizer.categorize("https://api.unknown-site.io/docs")
    assert_equal "Shopping", @categorizer.categorize("https://example.org/cart/checkout")
  end

  test "returns Other for blank, invalid or unrecognised URLs" do
    assert_equal "Other", @categorizer.categorize("")
    assert_equal "Other", @categorizer.categorize(nil)
    assert_equal "Other", @categorizer.categorize("http://exa mple.com")
    assert_equal "Other", @categorizer.categorize("https://example.org/")
  end

  test "every category used by the domain map has a colour" do
    UrlCategorizer::DOMAIN_CATEGORIES.values.uniq.each do |category|
      assert UrlCategorizer::CATEGORY_COLORS.key?(category), "missing colour for #{category}"
    end
  end
end
