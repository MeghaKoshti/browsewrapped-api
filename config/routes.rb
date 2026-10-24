Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      post "analyze", to: "analyses#analyze"
      resources :analyses, only: %i[create show destroy]
      resources :shared_reports, only: %i[create show destroy], param: :token
      get  "chrome",  to: "analyses#chrome"
      get  "sample",  to: "analyses#sample"
    end
  end
end
