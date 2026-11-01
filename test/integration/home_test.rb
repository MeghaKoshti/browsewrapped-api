require "test_helper"

class HomeTest < ActionDispatch::IntegrationTest
  test "the bare API URL answers with a JSON landing instead of a 404" do
    get "/"

    assert_response :ok
    body = response.parsed_body
    assert_equal "BrowseWrapped API", body["name"]
    assert_equal "ok", body["status"]
    assert_equal "/api/v1/sample", body["sample"]
  end
end
