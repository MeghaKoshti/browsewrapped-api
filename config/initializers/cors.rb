# Browser origins allowed to call the API, i.e. where the web app is hosted.
# CORS_ORIGINS is a comma-separated list of exact origins, for example
#   CORS_ORIGINS=https://browsewrapped.vercel.app,https://www.browsewrapped.dev
# Development and test also allow the Vite dev server. In production nothing
# is allowed until CORS_ORIGINS is set.
module CorsOrigins
  LOCAL = %w[http://localhost:5173 http://localhost:3001 http://127.0.0.1:5173].freeze

  module_function

  def list(env: ENV, local: Rails.env.local?)
    configured = env.fetch("CORS_ORIGINS", "").split(",")
                    .map { |origin| origin.strip.delete_suffix("/") }
                    .reject(&:empty?)

    (local ? LOCAL + configured : configured).uniq
  end
end

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins CorsOrigins.list

    resource "*",
      headers: :any,
      expose: %w[Location Retry-After],
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ]
  end
end
