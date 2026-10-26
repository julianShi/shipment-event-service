Rails.application.routes.draw do
  post "/webhooks/carrier_events", to: "carrier_events#create"
  get "/shipment_events", to: "shipment_events#index"
  get "/shipments", to: "shipments#index"
  get "/shipments/:shipment_reference", to: "shipments#show"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
