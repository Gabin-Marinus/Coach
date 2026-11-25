# app/controllers/meals_controller.rb
class MealsController < ApplicationController
  def update
    meal = current_user.meals.find(params[:id])
    meal.update(status: params[:status]) if Meal::STATUSES.include?(params[:status])
    redirect_back fallback_location: meals_profile_path
  end
end
