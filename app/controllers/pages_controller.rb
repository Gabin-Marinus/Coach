class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: :home

  def home
    return unless user_signed_in?

    @user = current_user
    @plan = @user.current_plan
    @date = selected_date
    return if @plan.nil?

    @date = @date.clamp(@plan.start_date, @plan.end_date)
    @workouts = @plan.workouts.for_date(@date).order(:id)
    @meals = @plan.meals.for_date(@date).sort_by { |meal| Meal::MEAL_TYPES.keys.index(meal.meal_type) || 99 }
  end

  private

  # The dashboard shows today by default; ?date=YYYY-MM-DD shows another day
  def selected_date
    Date.iso8601(params[:date].to_s)
  rescue Date::Error
    Date.today
  end
end
