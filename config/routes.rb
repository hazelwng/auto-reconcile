Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"
  post "reconcile", to: "home#reconcile", as: :reconcile
  delete "reset",   to: "home#reset",     as: :reset_workspace

  resources :data_sources,        only: [ :index, :edit, :update ]
  resources :import_batches,      only: [ :new, :create, :show ]
  resources :reconciliation_runs, only: [ :new, :create, :show ]
end
