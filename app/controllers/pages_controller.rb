class PagesController < ApplicationController
  def home
    @plan = current_user.current_plan
    return if @plan.nil?

    @todays_meals = Meal.in_day_order(@plan.meals.for_date(Date.today))
    @todays_workout = @plan.workouts.for_date(Date.today).first
  end

  def weekly_meals
    @plan = current_user.current_plan
    return if @plan.nil?

    @week = (params[:week] || @plan.current_week).to_i.clamp(1, @plan.total_weeks)
    @summary = WeekSummary.new(@plan, @plan.week_dates(@week))
  end
end
