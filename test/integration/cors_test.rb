require "test_helper"

class CorsTest < ActionDispatch::IntegrationTest
  def preflight(origin)
    process :options, "/api/v1/analyses", headers: {
      "Origin" => origin,
      "Access-Control-Request-Method" => "POST"
    }
  end

  test "the Vite dev server is an allowed origin in development and test" do
    preflight("http://localhost:5173")

    assert_equal "http://localhost:5173", response.headers["Access-Control-Allow-Origin"]
    assert_includes response.headers["Access-Control-Allow-Methods"], "POST"
  end

  test "other origins get no CORS headers" do
    preflight("https://evil.example")

    assert_nil response.headers["Access-Control-Allow-Origin"]
  end

  test "simple requests expose Retry-After and Location to the web app" do
    get "/api/v1/sample", headers: { "Origin" => "http://localhost:5173" }

    assert_equal "http://localhost:5173", response.headers["Access-Control-Allow-Origin"]
    assert_match(/Retry-After/, response.headers["Access-Control-Expose-Headers"])
  end

  test "CORS_ORIGINS is a comma-separated list, trimmed" do
    env = { "CORS_ORIGINS" => " https://browsewrapped.vercel.app/ ,https://www.browsewrapped.dev,," }

    assert_equal %w[https://browsewrapped.vercel.app https://www.browsewrapped.dev], CorsOrigins.list(env: env, local: false)
  end

  test "production allows nothing until CORS_ORIGINS is set, development adds localhost" do
    assert_empty CorsOrigins.list(env: {}, local: false)
    assert_equal CorsOrigins::LOCAL + [ "https://app.example" ], CorsOrigins.list(env: { "CORS_ORIGINS" => "https://app.example" }, local: true)
  end
end
