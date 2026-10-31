# Absolute URLs for links the API hands out: pages of the web app (WEB_URL)
# and pages the API serves itself (API_PUBLIC_URL), e.g. share previews.
module AppUrls
  module_function

  def web(path = "")
    "#{ENV.fetch("WEB_URL", "http://localhost:5173").delete_suffix("/")}#{path}"
  end

  def api(path = "")
    "#{ENV.fetch("API_PUBLIC_URL", "http://localhost:3000").delete_suffix("/")}#{path}"
  end
end
