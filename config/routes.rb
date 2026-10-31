Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  root "home#show"

  namespace :api do
    namespace :v1 do
      post "analyze", to: "analyses#analyze"
      resources :analyses, only: %i[create show destroy]
      resources :shared_reports, only: %i[create show destroy], param: :token
      get  "chrome",  to: "analyses#chrome"
      get  "sample",  to: "analyses#sample"

      # Billing (Wrapped Pass)
      get  "pricing", to: "pricing#show"
      resources :checkouts, only: :create
      post "webhooks/billing", to: "billing_webhooks#create"
    end

    # Billing::FakeProvider's checkout page (404 in production).
    scope "v1/fake_checkout/:id", controller: "/fake_checkouts", as: "fake_checkout" do
      get  "", action: :show
      post "pay", action: :pay, as: :pay
      post "cancel", action: :cancel, as: :cancel
    end
  end
end
