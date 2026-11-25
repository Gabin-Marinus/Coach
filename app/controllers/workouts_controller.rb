class WorkoutsController < ApplicationController
  def update
    workout = current_user.workouts.find(params[:id])
    workout.update(status: params[:status]) if Workout::STATUSES.include?(params[:status])
    redirect_back fallback_location: workouts_profile_path
  end
end
