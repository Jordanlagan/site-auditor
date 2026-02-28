Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # API routes
  resources :audits, only: [ :create, :show, :index, :destroy ] do
    member do
      get :status
      get "pages/:page_id", to: "audits#page_details", as: :page_details
      post "export-slides", to: "audits#export_slides"
      get "wireframe-profile", to: "audits#wireframe_profile"
    end
    resources :wireframes, only: [ :index, :create ] do
      collection do
        post :stream
      end
    end
  end

  resources :wireframes, only: [ :show, :destroy ] do
    member do
      post :regenerate
    end
  end

  # Test management routes
  resources :test_groups, path: "test-groups" do
    member do
      post :toggle_active
    end
  end

  resources :tests do
    member do
      post :toggle_active
    end
    collection do
      post :import
      get :export
    end
  end
end
