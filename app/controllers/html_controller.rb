# Base for the few HTML pages the API serves (fake checkout, share previews,
# admin). The API has no sessions or cookies, so Rails' session-based CSRF
# protection can't work here; pages that change data protect their forms
# themselves (see Admin::BaseController).
class HtmlController < ActionController::Base
  skip_forgery_protection
  layout "html"
end
