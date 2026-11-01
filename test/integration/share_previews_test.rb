require "test_helper"
require "zlib"

class SharePreviewsTest < ActionDispatch::IntegrationTest
  # A real, tiny PNG: a single-colour image of the given size.
  def png(width: 1200, height: 630)
    chunk = ->(type, data) { [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N") }
    raw = ("\x00".b + ("\xFF".b * width * 3)) * height
    "\x89PNG\r\n\x1A\n".b + chunk.("IHDR", [ width, height, 8, 2, 0, 0, 0 ].pack("NNCCCCC")) +
      chunk.("IDAT", Zlib::Deflate.deflate(raw, 9)) + chunk.("IEND", "")
  end

  def upload(bytes, type = "image/png")
    Rack::Test::UploadedFile.new(StringIO.new(bytes), type, original_filename: "card.png")
  end

  def report
    { summary: { total_visits: 10 }, persona: { id: "builder", title: "The Builder <script>", description: "x" },
      top_pages: [ { url: "https://private.example/" } ] }
  end

  def share!(card: upload(png))
    post "/api/v1/shared_reports", params: { report: report.to_json, card: card }
    response.parsed_body
  end

  test "a share can carry a PNG card and returns a preview URL" do
    body = share!

    assert_response :created
    assert_equal "http://localhost:3000/s/#{body["token"]}", body["preview_url"]
    get "/api/v1/shared_reports/#{body["token"]}/card.png"
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_equal png, response.body.b
  end

  test "the multipart report is sanitised like the JSON one" do
    token = share!["token"]

    get "/api/v1/shared_reports/#{token}"

    assert_equal "The Builder <script>", response.parsed_body.dig("report", "persona", "title")
    assert_not response.parsed_body["report"].key?("top_pages")
  end

  test "a non-PNG card is refused with 415, whatever its content type says" do
    share!(card: upload("GIF89a fake image".b, "image/png"))

    assert_response :unsupported_media_type
    assert_equal "unsupported_media_type", response.parsed_body.dig("error", "code")
    assert_equal 0, SharedReport.count
  end

  test "a card over 300 KB is refused with 413" do
    share!(card: upload(png + ("\x00".b * 300.kilobytes)))

    assert_response :content_too_large
    assert_equal 0, SharedReport.count
  end

  test "a card of the wrong size is refused" do
    share!(card: upload(png(width: 1080, height: 1350)))

    assert_response :unprocessable_entity
    assert_equal "invalid_card_dimensions", response.parsed_body.dig("error", "code")
  end

  test "the JSON body without a card still works, and has no card image" do
    post "/api/v1/shared_reports", params: { report: report }, as: :json
    token = response.parsed_body["token"]

    assert_response :created
    get "/api/v1/shared_reports/#{token}/card.png"
    assert_response :not_found
  end

  test "/s/:token has Open Graph and Twitter tags and redirects to the web app" do
    token = share!["token"]

    get "/s/#{token}"

    assert_response :success
    html = Nokogiri::HTML(response.body)
    meta = ->(attr, name) { html.at_css("meta[#{attr}='#{name}']")&.[]("content") }
    assert_equal "I'm The Builder <script> · My BrowseWrapped", meta.("property", "og:title")
    assert_equal "http://localhost:3000/api/v1/shared_reports/#{token}/card.png", meta.("property", "og:image")
    assert_equal "summary_large_image", meta.("name", "twitter:card")
    assert meta.("property", "og:description").present?
    assert_equal "0; url=http://localhost:5173/r/#{token}", meta.("http-equiv", "refresh")
    assert_not_includes response.body, "<script>"
  end

  test "/s/:token without a card falls back to the default image" do
    post "/api/v1/shared_reports", params: { report: report }, as: :json

    get "/s/#{response.parsed_body["token"]}"

    assert_includes response.body, %(content="http://localhost:5173/og-image.png")
  end

  test "unknown and expired shares get a 404 with generic tags and no redirect" do
    token = share!["token"]

    get "/s/unknown"
    assert_response :not_found
    assert_includes response.body, %(property="og:title" content="BrowseWrapped: your browsing year, wrapped")
    assert_not_includes response.body, "refresh"

    travel 31.days do
      get "/s/#{token}"
      assert_response :not_found
      get "/api/v1/shared_reports/#{token}/card.png"
      assert_response :not_found
    end
  end

  test "deleting the share deletes its card" do
    body = share!

    delete "/api/v1/shared_reports/#{body["token"]}", headers: { "X-Delete-Token" => body["delete_token"] }

    assert_response :no_content
    assert_equal 0, ShareCard.count
  end

  test "the expiry cleanup removes cards too" do
    share!

    travel(31.days) { CleanupExpiredSharedReportsJob.perform_now }

    assert_equal 0, ShareCard.count
  end
end
