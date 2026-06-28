require "uri"
require "cgi"

class UrlCategorizer
  DOMAIN_CATEGORIES = {
    # Programming
    "github.com" => "Programming", "stackoverflow.com" => "Programming",
    "gitlab.com" => "Programming", "npmjs.com" => "Programming",
    "pypi.org" => "Programming", "rubygems.org" => "Programming",
    "docker.com" => "Programming", "hub.docker.com" => "Programming",
    "kubernetes.io" => "Programming", "developer.mozilla.org" => "Programming",
    "devdocs.io" => "Programming", "w3schools.com" => "Programming",
    "css-tricks.com" => "Programming", "dev.to" => "Programming",
    "hashnode.com" => "Programming", "codepen.io" => "Programming",
    "jsfiddle.net" => "Programming", "replit.com" => "Programming",
    "codesandbox.io" => "Programming", "leetcode.com" => "Programming",
    "hackerrank.com" => "Programming", "codeforces.com" => "Programming",
    "geeksforgeeks.org" => "Programming", "freecodecamp.org" => "Programming",
    "theodinproject.com" => "Programming", "codecademy.com" => "Programming",
    "exercism.org" => "Programming", "exercism.io" => "Programming",
    "raycast.com" => "Programming", "docs.rs" => "Programming",
    "pkg.go.dev" => "Programming", "crates.io" => "Programming",
    "hackage.haskell.org" => "Programming",

    # Cloud & DevOps
    "vercel.com" => "Cloud & DevOps", "netlify.com" => "Cloud & DevOps",
    "heroku.com" => "Cloud & DevOps", "aws.amazon.com" => "Cloud & DevOps",
    "console.aws.amazon.com" => "Cloud & DevOps", "cloud.google.com" => "Cloud & DevOps",
    "portal.azure.com" => "Cloud & DevOps", "digitalocean.com" => "Cloud & DevOps",
    "fly.io" => "Cloud & DevOps", "railway.app" => "Cloud & DevOps",
    "render.com" => "Cloud & DevOps", "cloudflare.com" => "Cloud & DevOps",

    # AI & ML
    "huggingface.co" => "AI & ML", "paperswithcode.com" => "AI & ML",
    "tensorflow.org" => "AI & ML", "pytorch.org" => "AI & ML",
    "deeplearning.ai" => "AI & ML", "fast.ai" => "AI & ML",
    "openai.com" => "AI & ML", "anthropic.com" => "AI & ML",
    "chat.openai.com" => "AI & ML", "claude.ai" => "AI & ML",
    "gemini.google.com" => "AI & ML", "perplexity.ai" => "AI & ML",
    "midjourney.com" => "AI & ML", "stability.ai" => "AI & ML",
    "replicate.com" => "AI & ML", "ollama.com" => "AI & ML",
    "lmsys.org" => "AI & ML", "together.ai" => "AI & ML",

    # Data Science
    "kaggle.com" => "Data Science", "colab.research.google.com" => "Data Science",
    "towardsdatascience.com" => "Data Science", "analyticsvidhya.com" => "Data Science",
    "databricks.com" => "Data Science", "snowflake.com" => "Data Science",
    "mode.com" => "Data Science", "hex.tech" => "Data Science",

    # Design
    "figma.com" => "Design", "behance.net" => "Design",
    "dribbble.com" => "Design", "adobe.com" => "Design",
    "canva.com" => "Design", "coolors.co" => "Design",
    "fonts.google.com" => "Design", "unsplash.com" => "Design",
    "smashingmagazine.com" => "Design", "uxdesign.cc" => "Design",
    "material.io" => "Design", "fontawesome.com" => "Design",
    "framer.com" => "Design", "sketch.com" => "Design",
    "invisionapp.com" => "Design", "zeplin.io" => "Design",
    "pexels.com" => "Design", "pixabay.com" => "Design",

    # Social Media
    "twitter.com" => "Social Media", "x.com" => "Social Media",
    "facebook.com" => "Social Media", "instagram.com" => "Social Media",
    "linkedin.com" => "Social Media", "reddit.com" => "Social Media",
    "tiktok.com" => "Social Media", "discord.com" => "Social Media",
    "telegram.org" => "Social Media", "whatsapp.com" => "Social Media",
    "mastodon.social" => "Social Media", "threads.net" => "Social Media",
    "snapchat.com" => "Social Media", "pinterest.com" => "Social Media",
    "tumblr.com" => "Social Media", "bluesky.app" => "Social Media",

    # Entertainment
    "youtube.com" => "Entertainment", "youtu.be" => "Entertainment",
    "netflix.com" => "Entertainment", "spotify.com" => "Entertainment",
    "twitch.tv" => "Entertainment", "hulu.com" => "Entertainment",
    "disneyplus.com" => "Entertainment", "primevideo.com" => "Entertainment",
    "max.com" => "Entertainment", "imdb.com" => "Entertainment",
    "soundcloud.com" => "Entertainment", "bandcamp.com" => "Entertainment",
    "rottentomatoes.com" => "Entertainment", "letterboxd.com" => "Entertainment",
    "last.fm" => "Entertainment", "crunchyroll.com" => "Entertainment",

    # Tech News
    "news.ycombinator.com" => "Tech News", "techcrunch.com" => "Tech News",
    "theverge.com" => "Tech News", "wired.com" => "Tech News",
    "arstechnica.com" => "Tech News", "hackernoon.com" => "Tech News",
    "thenextweb.com" => "Tech News", "venturebeat.com" => "Tech News",
    "zdnet.com" => "Tech News", "infoq.com" => "Tech News",
    "lobste.rs" => "Tech News",

    # News
    "nytimes.com" => "News", "bbc.com" => "News", "bbc.co.uk" => "News",
    "cnn.com" => "News", "washingtonpost.com" => "News",
    "theguardian.com" => "News", "reuters.com" => "News",
    "apnews.com" => "News", "npr.org" => "News",

    # Finance
    "bloomberg.com" => "Finance", "wsj.com" => "Finance",
    "ft.com" => "Finance", "coinbase.com" => "Finance",
    "robinhood.com" => "Finance", "tradingview.com" => "Finance",
    "paypal.com" => "Finance", "stripe.com" => "Finance",
    "binance.com" => "Finance", "kraken.com" => "Finance",
    "fidelity.com" => "Finance", "schwab.com" => "Finance",

    # Education
    "coursera.org" => "Education", "udemy.com" => "Education",
    "edx.org" => "Education", "pluralsight.com" => "Education",
    "khanacademy.org" => "Education", "duolingo.com" => "Education",
    "brilliant.org" => "Education", "skillshare.com" => "Education",
    "udacity.com" => "Education", "egghead.io" => "Education",
    "frontendmasters.com" => "Education", "laracasts.com" => "Education",
    "scrimba.com" => "Education", "linkedin.com/learning" => "Education",

    # Shopping
    "amazon.com" => "Shopping", "ebay.com" => "Shopping",
    "etsy.com" => "Shopping", "walmart.com" => "Shopping",
    "bestbuy.com" => "Shopping", "target.com" => "Shopping",
    "aliexpress.com" => "Shopping", "shopify.com" => "Shopping",

    # Productivity
    "notion.so" => "Productivity", "trello.com" => "Productivity",
    "asana.com" => "Productivity", "slack.com" => "Productivity",
    "zoom.us" => "Productivity", "docs.google.com" => "Productivity",
    "sheets.google.com" => "Productivity", "drive.google.com" => "Productivity",
    "mail.google.com" => "Productivity", "calendar.google.com" => "Productivity",
    "jira.atlassian.com" => "Productivity", "confluence.atlassian.com" => "Productivity",
    "linear.app" => "Productivity", "airtable.com" => "Productivity",
    "clickup.com" => "Productivity", "obsidian.md" => "Productivity",
    "roamresearch.com" => "Productivity", "logseq.com" => "Productivity",
    "miro.com" => "Productivity", "loom.com" => "Productivity",

    # Science & Research
    "nature.com" => "Science", "arxiv.org" => "Science",
    "pubmed.ncbi.nlm.nih.gov" => "Science", "researchgate.net" => "Science",
    "semanticscholar.org" => "Science", "ncbi.nlm.nih.gov" => "Science",
    "scholar.google.com" => "Reference", "wikipedia.org" => "Reference",
    "britannica.com" => "Reference", "wolframalpha.com" => "Reference",

    # Gaming
    "steampowered.com" => "Gaming", "store.steampowered.com" => "Gaming",
    "itch.io" => "Gaming", "epicgames.com" => "Gaming",
    "battle.net" => "Gaming", "chess.com" => "Gaming",
    "lichess.org" => "Gaming", "roblox.com" => "Gaming",
    "gog.com" => "Gaming", "polygon.com" => "Gaming",

    # Travel
    "airbnb.com" => "Travel", "booking.com" => "Travel",
    "tripadvisor.com" => "Travel", "expedia.com" => "Travel",
    "skyscanner.com" => "Travel", "kayak.com" => "Travel",

    # Health
    "webmd.com" => "Health", "mayoclinic.org" => "Health",
    "healthline.com" => "Health", "myfitnesspal.com" => "Health",
    "strava.com" => "Health", "nike.com" => "Health",

    # Search (special — extract queries separately)
    "google.com" => "Search", "bing.com" => "Search",
    "duckduckgo.com" => "Search", "search.yahoo.com" => "Search",
    "startpage.com" => "Search", "brave.com" => "Search",
  }.freeze

  CATEGORY_COLORS = {
    "Programming"   => "#6366f1",
    "Cloud & DevOps" => "#06b6d4",
    "AI & ML"       => "#a855f7",
    "Data Science"  => "#ec4899",
    "Design"        => "#f97316",
    "Social Media"  => "#3b82f6",
    "Entertainment" => "#ef4444",
    "Tech News"     => "#eab308",
    "News"          => "#84cc16",
    "Finance"       => "#10b981",
    "Education"     => "#14b8a6",
    "Shopping"      => "#f43f5e",
    "Productivity"  => "#8b5cf6",
    "Science"       => "#0ea5e9",
    "Reference"     => "#64748b",
    "Gaming"        => "#d946ef",
    "Travel"        => "#22c55e",
    "Health"        => "#4ade80",
    "Search"        => "#94a3b8",
    "Other"         => "#475569",
  }.freeze

  def categorize(url)
    return "Other" if url.blank?
    uri = URI.parse(url)
    host = uri.host&.downcase&.sub(/^www\./, "")
    return "Other" unless host

    DOMAIN_CATEGORIES[host] ||
      DOMAIN_CATEGORIES.find { |d, _| host.end_with?(".#{d}") }&.last ||
      keyword_fallback(host, uri.path.to_s)
  rescue URI::InvalidURIError
    "Other"
  end

  private

  def keyword_fallback(host, path)
    text = "#{host} #{path}".downcase
    return "Programming"    if text.match?(/code|dev|git|api|sdk|npm|gem|package|stack|overflow|program|debug/)
    return "AI & ML"        if text.match?(/\bai\b|ml\b|machine.learn|neural|gpt|llm|chatbot|diffus/)
    return "Education"      if text.match?(/learn|course|tutorial|edu\b|academy|school|university|college|mooc/)
    return "Entertainment"  if text.match?(/video|stream|watch|movie|music|podcast|episode/)
    return "News"           if text.match?(/news|blog|press|article|media|journal|magazine/)
    return "Shopping"       if text.match?(/shop|store|buy|cart|product|checkout|price/)
    return "Finance"        if text.match?(/bank|finance|money|invest|crypto|trade|stock/)
    return "Health"         if text.match?(/health|medical|doctor|fitness|wellness|symptom/)
    return "Travel"         if text.match?(/travel|hotel|flight|trip|vacation|booking|airport/)
    return "Gaming"         if text.match?(/game|gaming|play|gamer|esport/)
    "Other"
  end
end
