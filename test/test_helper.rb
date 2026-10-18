ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Builds one normalised history entry, the same shape HistoryParser returns.
    def entry(url, visited_at: Time.utc(2026, 6, 1, 10), title: "", visit_count: 1)
      { url: url, title: title, visited_at: visited_at, visit_count: visit_count }
    end
  end
end
