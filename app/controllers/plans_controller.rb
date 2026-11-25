class PlansController < ApplicationController
  def create
    @chat = current_user.chats.plan_chats.find(params[:chat_id])

    unless current_user.ready_for_plan?
      redirect_to edit_profile_path, alert: "Please complete your profile and goals before saving a plan."
      return
    end

    PlanGenerator.new(@chat).call
    redirect_to workouts_profile_path, notice: "Your 3-month plan was saved! 🎉"
  rescue JSON::ParserError, ActiveRecord::RecordInvalid, RubyLLM::Error
    redirect_to chat_path(@chat), alert: "Sorry, we couldn't save your plan. Please try again."
  end
end
