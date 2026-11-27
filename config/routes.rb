Rails.application.routes.draw do
  devise_for :users
  root to: "pages#home"

  resource :profile, only: [:show, :edit, :update] do
    get :plan
    get :plans
    get :workouts
    get :meals
    patch :theme # light / dark switch in the navbar
  end

  resources :chats, only: [:index, :show, :create, :destroy] do
    resources :messages, only: [:create]
    resources :plans, only: [:create]
  end

  # Floating coach button
  resource :coach, only: [:show], controller: "coach" do
    post :ask
    post :reset
  end

  resources :plans, only: [:destroy] do
    post :summary, on: :member
    post :shopping_list, on: :member
    get :calendar, on: :member
    delete :destroy_many, on: :collection
  end

  resources :workouts, only: [:update]
  resources :meals, only: [:update]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Installable app ("Add to Home Screen" on a phone): name, icon and colors (app/views/pwa/manifest.json.erb)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
end
