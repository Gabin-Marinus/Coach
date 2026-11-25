Rails.application.routes.draw do
  devise_for :users
  root to: "pages#home"
  get "weekly-meals", to: "pages#weekly_meals", as: :weekly_meals

  resource :profile, only: [:show, :edit, :update] do
    get :plan
    get :workouts
    get :meals
  end

  resources :chats, only: [:index, :show, :create, :destroy] do
    resources :messages, only: [:create]
    resources :plans, only: [:create]
  end

  resources :workouts, only: [:update]
  resources :meals, only: [:update]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
