require "test_helper"

class PrivacyTest < ActionDispatch::IntegrationTest
  def with_env(key, value)
    original = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = original
  end

  # Swaps in a logger that writes to a string for the duration of the block.
  def capture_logs
    io = StringIO.new
    original = ActionController::Base.logger
    ActionController::Base.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    ActionController::Base.logger = original
  end

  test "a posted report is filtered from the request log" do
    report = { summary: { total_visits: 3 }, top_pages: [ { url: "https://secret.example/diagnosis", title: "Private" } ] }

    log = capture_logs { post "/api/v1/shared_reports", params: { report: report }, as: :json }

    assert_response :created
    assert_match(/"report"\s*=>\s*"\[FILTERED\]"/, log) # Hash#inspect spacing differs across Ruby versions
    assert_not_includes log, "secret.example"
  end

  test "local Chrome import is off unless LOCAL_CHROME_IMPORT=on" do
    get "/api/v1/chrome"

    assert_response :not_found
    assert_equal "disabled", response.parsed_body.dig("error", "code")
  end

  test "with LOCAL_CHROME_IMPORT=on the endpoint reads the local Chrome history" do
    with_env("LOCAL_CHROME_IMPORT", "on") { get "/api/v1/chrome" }

    # No Chrome on the CI machine, but the request got past the switch.
    assert_not_equal "disabled", response.parsed_body.dig("error", "code")
  end
end
