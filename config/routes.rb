Rails.application.routes.draw do
  devise_for :users,
             only: [ :sessions, :registrations, :omniauth_callbacks ],
             controllers: {
               registrations: "users/registrations",
               omniauth_callbacks: "users/omniauth_callbacks"
             }

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  get "status" => "status#show"
  get "srd" => "srd#show", as: :srd
  get "srd/" => "srd#show"
  get "astrogation" => "astrogation#show", as: :astrogation
  get "manual" => "manual#index", as: :manual
  get "manual/" => "manual#index"
  get "manual/:slug" => "manual#show", as: :manual_page
  namespace :webadmin do
    resources :manual_pages, only: [ :index, :new, :create, :edit, :update ] do
      match :preview, on: :collection, via: [ :post, :patch ]
    end
  end
  resource :profile, only: [ :show, :edit, :update ]
  get "profiles/:id" => "profiles#show", as: :view_profile
  delete "logout" => "sessions#destroy", as: :logout
  root "landing#show"

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
