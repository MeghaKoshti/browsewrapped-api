require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  include BillingHelpers # with_env

  CREDENTIALS = { "ADMIN_USER" => "megha", "ADMIN_PASSWORD" => "s3cret-pass" }.freeze

  def auth(user = "megha", password = "s3cret-pass")
    { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(user, password) }
  end

  def form_token
    get "/admin", headers: auth
    Nokogiri::HTML(response.body).at_css("input[name=form_token]")["value"]
  end

  test "/admin is 404 when no credentials are configured" do
    with_env("ADMIN_USER" => nil, "ADMIN_PASSWORD" => nil) { get "/admin", headers: auth }

    assert_response :not_found
  end

  test "/admin asks for credentials and refuses wrong ones" do
    with_env(CREDENTIALS) do
      get "/admin"
      assert_response :unauthorized

      get "/admin", headers: auth("megha", "wrong")
      assert_response :unauthorized
    end
  end

  test "the dashboard shows today's numbers" do
    Analysis.create!(status: :completed, result: {})
    Analysis.create!(status: :failed, error_message: "The file is empty")
    Purchase.record_payment!(email: "a@b.co", plan: "wrapped_pass", amount: 19_900, currency: "INR", provider: "fake", provider_ref: "p1")

    with_env(CREDENTIALS) { get "/admin", headers: auth }

    assert_response :success
    assert_includes response.body, "completed: 1"
    assert_includes response.body, "The file is empty"
    assert_includes response.body, "INR 199.00"
    assert_includes response.body, "0 / 2000"
  end

  test "a manual category wins over the AI answer" do
    DomainCategory.create!(domain: "tailwindcss.com", category: "Shopping", source: "ai", confidence: 0.6)

    with_env(CREDENTIALS) do
      post "/admin/domain_categories", params: { domain: "www.TailwindCSS.com", category: "Design", form_token: form_token }, headers: auth
    end

    assert_redirected_to "/admin?saved=tailwindcss.com"
    row = DomainCategory.sole
    assert_equal [ "Design", "manual", nil ], [ row.category, row.source, row.confidence ]
    result = AiDomainCategorizer.new([ entry("https://tailwindcss.com/docs") ], classifier: AiBudgetTest::CountingClassifier.new).call
    assert_equal({ "tailwindcss.com" => "Design" }, result.overrides)
  end

  test "posting without the form token is refused" do
    with_env(CREDENTIALS) do
      post "/admin/domain_categories", params: { domain: "x.dev", category: "Design" }, headers: auth
    end

    assert_response :unprocessable_entity
    assert_equal 0, DomainCategory.count
  end

  test "an unknown category is refused" do
    with_env(CREDENTIALS) do
      post "/admin/domain_categories", params: { domain: "x.dev", category: "Astrology", form_token: form_token }, headers: auth
    end

    assert_response :unprocessable_entity
  end
end
