Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      post "analyze", to: "analyses#create"
      get  "chrome",  to: "analyses#chrome"
    end
  end
end
