class ProfilesController < ApplicationController
  before_action :set_user
  helper_method :plan_params

  def show
  end

  def edit
  end

  # Sun/moon button in the navbar: switches the design right away (only this setting, no profile checks)
  def theme
    @user.update(theme: params[:theme]) if User::THEMES.key?(params[:theme])
    redirect_back fallback_location: root_path, status: :see_other
  end

  def update
    @user.assign_attributes(profile_params)

    if @user.save(context: :profile)
      redirect_to profile_path, notice: "Your profile is saved!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def workouts
    load_week
    @workouts_by_date = @plan ? @plan.workouts.where(date: @dates).order(:date).group_by(&:date) : {}
  end

  def meals
    load_week
    @meals_by_date = @plan ? @plan.meals.where(date: @dates).order(:date).group_by(&:date) : {}
  end

  def plan
    load_week
    return if @plan.nil?

    @workouts_by_date = @plan.workouts.where(date: @dates).order(:date).group_by(&:date)
    @meals_by_date    = @plan.meals.where(date: @dates).order(:date).group_by(&:date)
  end

  # All the user's plans, newest first, with done / total counts
  def plans
    @plans = @user.plans.order(created_at: :desc)
    @workout_counts = Workout.where(plan: @plans).group(:plan_id, :status).count
    @meal_counts = Meal.where(plan: @plans).group(:plan_id, :status).count
  end

  private

  def set_user
    @user = current_user
  end

  # Shows the current plan, or an older one with ?plan_id=
  def load_week
    @plan = params[:plan_id].present? ? @user.plans.find(params[:plan_id]) : @user.current_plan
    return if @plan.nil?

    @week = (params[:week] || @plan.current_week).to_i.clamp(1, @plan.total_weeks)
    @dates = @plan.week_dates(@week)
  end

  # Link params for the plan pages; keeps an older plan selected
  def plan_params(week)
    { week: week, plan_id: (@plan.id if @plan && @plan != @user.current_plan) }.compact
  end

  def profile_params
    params.require(:user).permit(
      :birth_date, :sex, :height_cm, :current_weight_kg, :target_weight_kg,
      :activity_level, :diet_type, :food_dislikes, :meals_per_day, :cooking_time,
      :fitness_level, :training_location, :training_days_per_week,
      :session_minutes, :preferred_time, :injury_notes, :exercise_dislikes,
      :city, :country, :food_budget, :food_budget_period, :currency, :favorite_meals, :regular_sessions, :theme,
      allergies: [], exercise_types: [], equipment: [], injuries: [], goals: []
    )
  end
end
