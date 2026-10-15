Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  root "dashboard#show"
  resources :operations, only: :update
  resources :orders, only: :create
  resources :catalogue_syncs, only: :create
end
