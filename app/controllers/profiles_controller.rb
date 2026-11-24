class ProfilesController < ApplicationController
  before_action :set_user

  def show
  end

  def edit
  end

  def update
    @user.assign_attributes(profile_params)

    if @user.save(context: :profile)
      redirect_to profile_path, notice: "Your profile is saved!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = current_user
  end

  def profile_params
    params.require(:user).permit(
      :birth_date, :sex, :height_cm, :current_weight_kg, :target_weight_kg,
      :activity_level, :diet_type, :food_dislikes, :meals_per_day, :cooking_time,
      :fitness_level, :training_location, :training_days_per_week,
      :session_minutes, :preferred_time, :injury_notes, :exercise_dislikes,
      allergies: [], exercise_types: [], equipment: [], injuries: [], goals: []
    )
  end
end
