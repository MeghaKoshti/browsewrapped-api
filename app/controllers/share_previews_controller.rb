# GET /s/:token
#
# The link people actually share. Link-preview bots (WhatsApp, X, LinkedIn,
# Slack) don't run JavaScript, so the web app's /r/:token page looks blank to
# them. This tiny server-rendered page carries the Open Graph and Twitter tags
# and sends real visitors on to ${WEB_URL}/r/:token.
class SharePreviewsController < HtmlController
  def show
    @shared_report = SharedReport.active.includes(:card).find_by(token: params[:token].to_s)
    @web_url = AppUrls.web("/r/#{@shared_report.token}") if @shared_report
    render status: @shared_report ? :ok : :not_found
  end

  private

  helper_method :og_title, :og_description, :og_image

  def og_title
    title = @shared_report&.persona_title
    title ? "I'm #{title.truncate(60)} · My BrowseWrapped" : "BrowseWrapped: your browsing year, wrapped"
  end

  def og_description
    if @shared_report
      "See my browsing Wrapped: top topics, daily rhythm and streaks. Make your own from your browser history."
    else
      "Turn your browser history into a Wrapped-style report: persona, top topics, rhythm and streaks."
    end
  end

  def og_image
    if @shared_report&.card
      AppUrls.api("/api/v1/shared_reports/#{@shared_report.token}/card.png")
    else
      ENV.fetch("OG_FALLBACK_IMAGE_URL") { AppUrls.web("/og-image.png") }
    end
  end
end
