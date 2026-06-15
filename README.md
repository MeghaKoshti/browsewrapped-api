# BrowseWrapped API

BrowseWrapped API powers the analytics engine behind BrowseWrapped.

The API processes browser history data and generates insights about learning patterns, interests, browsing behavior, and knowledge evolution.

## Responsibilities

### Data Processing

* Browser history ingestion
* URL normalization
* Domain classification
* Topic extraction
* Analytics generation

### Insights Engine

* Interest trend analysis
* Knowledge mapping
* Learning timeline generation
* Search evolution tracking
* Topic clustering

### Reporting

* Wrapped-style summaries
* Activity statistics
* Historical comparisons
* Personalized insights

## Tech Stack

* Ruby on Rails API
* PostgreSQL
* Redis
* Sidekiq
* RSpec

## Development

### Prerequisites

* Ruby
* PostgreSQL
* Redis

If using mise:

```bash
mise install
mise trust
```

### Setup

```bash
bundle install
rails db:create
rails db:migrate
```

### Run Server

```bash
rails s
```

### Run Background Jobs

```bash
bundle exec sidekiq
```

### Run Tests

```bash
bundle exec rspec
```

## Architecture

```text
Browser History
       ↓
Upload API
       ↓
Processing Pipeline
       ↓
Topic Classification
       ↓
Analytics Engine
       ↓
Insights & Visualizations
```

## Frontend Repository

https://github.com/MeghaKoshti/browsewrapped-web

## Project Status

🚧 Early Development

Planned features:

* Browser history import
* Topic extraction
* Knowledge graph generation
* Interest trend analytics
* Personalized yearly reports

## Author

Megha Koshti
