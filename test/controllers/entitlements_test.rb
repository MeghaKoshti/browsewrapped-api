require "test_helper"

class EntitlementsTest < ActionDispatch::IntegrationTest
  class PassOnlyController < ApplicationController
    before_action :require_pass!

    def show
      render json: { ok: true }
    end
  end

  # => [status, parsed body]; with_routing drops the response after its block.
  def call_gated(headers = {})
    with_routing do |set|
      set.draw { get "/gated", to: "entitlements_test/pass_only#show" }
      get "/gated", headers: headers
      [ response.status, response.parsed_body ]
    end
  end

  def bearer(email)
    { "Authorization" => "Bearer #{PassSession.issue(email)}" }
  end

  test "require_pass! answers 402 pass_required without a session or Pass" do
    status, body = call_gated
    assert_equal 402, status
    assert_equal "pass_required", body.dig("error", "code")

    assert_equal 402, call_gated(bearer("free@example.com")).first
  end

  test "require_pass! lets Pass holders through" do
    Purchase.record_payment!(email: "paid@example.com", plan: "wrapped_pass", amount: 500, currency: "USD", provider: "fake", provider_ref: "p1")

    assert_equal [ 200, { "ok" => true } ], call_gated(bearer("paid@example.com"))
  end

  test "an expired Pass is no Pass" do
    Purchase.record_payment!(email: "paid@example.com", plan: "wrapped_pass", amount: 500, currency: "USD", provider: "fake", provider_ref: "p1")

    travel 366.days do
      assert_equal 402, call_gated(bearer("paid@example.com")).first
    end
  end
end
