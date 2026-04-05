Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      post "auth/register", to: "auth#register"
      post "auth/login", to: "auth#login"

      resources :events do
        resources :ticket_tiers, only: [:index, :create, :update, :destroy]
      end

      get "bookmarks", to: "bookmarks#index"
      post "events/:event_id/bookmarks", to: "bookmarks#create"
      delete "events/:event_id/bookmarks", to: "bookmarks#destroy"

      resources :orders, only: [:index, :show, :create] do
        member do
          post :cancel
        end
      end
    end
  end
end
