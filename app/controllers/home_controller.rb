# GET / — a small JSON landing so the API's bare URL answers with something
# useful (it used to be a 404) and uptime monitors have a friendly target.
class HomeController < ApplicationController
  def show
    render json: {
      name: "BrowseWrapped API",
      status: "ok",
      web: ENV.fetch("WEB_URL", "http://localhost:5173"),
      docs: "https://github.com/MeghaKoshti/browsewrapped-api#api",
      health: "/up",
      sample: "/api/v1/sample"
    }
  end
end
