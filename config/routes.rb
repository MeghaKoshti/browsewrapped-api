Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  root "home#show"

  # Owner-only dashboard (HTTP Basic; 404 unless ADMIN_USER and ADMIN_PASSWORD are set).
  namespace :admin do
    root "dashboard#show"
    resources :domain_categories, only: :create
  end

  # Link-preview page for shared reports (Open Graph tags + redirect to the web app).
  get "s/:token", to: "share_previews#show", as: :share_preview, format: false

  namespace :api do
    namespace :v1 do
      post "analyze", to: "analyses#analyze"
      resources :analyses, only: %i[create show destroy]
      resources :shared_reports, only: %i[create show destroy], param: :token
      get "shared_reports/:token/card.png", to: "shared_reports#card", as: :shared_report_card, format: false
      get  "chrome",  to: "analyses#chrome"
      get  "sample",  to: "analyses#sample"

      # Billing (Wrapped Pass)
      get  "pricing", to: "pricing#show"
      resources :checkouts, only: :create
      post "webhooks/billing", to: "billing_webhooks#create"

      # Pass holders: magic-link sign-in
      post "sessions/magic_link", to: "sessions#magic_link"
      post "sessions/verify",     to: "sessions#verify"
      get  "me",                  to: "me#show"
    end

    # Billing::FakeProvider's checkout page (404 in production).
    scope "v1/fake_checkout/:id", controller: "/fake_checkouts", as: "fake_checkout" do
      get  "", action: :show
      post "pay", action: :pay, as: :pay
      post "cancel", action: :cancel, as: :cancel
    end
  end
end
