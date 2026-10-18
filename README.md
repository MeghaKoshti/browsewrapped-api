# BrowseWrapped API

**The Rails API behind BrowseWrapped.** It takes a browser-history export, classifies every URL into topics, and returns a "Wrapped"-style analytics report as JSON: persona, trends, heatmaps, sessions, streaks and a topic knowledge graph.

Frontend: [browsewrapped-web](https://github.com/MeghaKoshti/browsewrapped-web)

![BrowseWrapped results page](https://raw.githubusercontent.com/MeghaKoshti/browsewrapped-web/main/docs/screenshots/wrapped.jpg)

## How it works

```text
Upload (JSON / CSV)  or  local Chrome history (SQLite)
              │
              ▼
   HistoryParser        → normalises entries: url, title, visited_at, visit_count
              │
              ▼
   UrlCategorizer       → maps domains/URLs to topics (Programming, AI & ML, News…)
              │
              ▼
   HistoryAnalyzer      → builds the report: summary, persona, patterns, trends, graph
              │
              ▼
        JSON response   → rendered by browsewrapped-web
```

History is processed **in memory for each request**. Nothing from the uploaded file is saved to the database.

## API

### `POST /api/v1/analyze`

Upload a history file as multipart form data (`file`, max 100 MB).

Supported formats:

- **Chrome Takeout:** `BrowserHistory.json` (`{ "Browser History": [...] }`)
- **JSON array:** `[{ "url", "title", "visitTime", "visitCount" }, ...]` (typical extension export)
- **CSV:** any file with a `url` column (title, time and count columns are detected automatically)

```bash
curl -F file=@sample/sample_history.json http://localhost:3000/api/v1/analyze
```

### `GET /api/v1/chrome`

Reads the local Chrome/Chromium history database directly (Linux and macOS), for when the API runs on your own machine.

### Response (top-level keys)

`summary`, `persona`, `topics`, `time_by_topic`, `daily_pattern`, `weekly_pattern`, `monthly_trends`, `heatmap`, `activity_calendar`, `sessions`, `streaks`, `topic_momentum`, `top_domains`, `top_pages`, `top_searches`, `chrome_searches`, `intent`, `knowledge_graph`, `meta`

## Tech stack

- Ruby on Rails 8.1 (API mode)
- PostgreSQL
- SQLite3 (to read Chrome's local history file)
- Rack CORS (allows the Vite dev server on `localhost:5173`)

## Getting started

### Prerequisites

- Ruby 3.4 (see `.ruby-version`; `mise install` works too)
- PostgreSQL running locally

### Setup

```bash
bundle install
bin/rails db:prepare
bin/rails server        # http://localhost:3000
```

Then start [browsewrapped-web](https://github.com/MeghaKoshti/browsewrapped-web) and upload `sample/sample_history.json`.

### Sample data

`sample/sample_history.json` is a **synthetic** file (about 1,250 visits over 60 days of developer-style browsing), so you can try the app without exporting your own history.

## Project status

🚧 Actively in development. Next up: automated tests (RSpec), background processing for very large files, and shareable reports.

## Author

**Megha Koshti**, Ruby on Rails developer · [GitHub](https://github.com/MeghaKoshti) · [LinkedIn](https://www.linkedin.com/in/megha-koshti)

## License

[MIT](LICENSE)
