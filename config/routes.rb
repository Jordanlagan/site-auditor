Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # API routes
  resources :audits, only: [ :create, :show, :index, :destroy ] do
    member do
      get :status
      get "pages/:page_id", to: "audits#page_details", as: :page_details
    end
  end
end
