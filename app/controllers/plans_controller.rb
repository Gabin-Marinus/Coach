class PlansController < ApplicationController
  def create
    @chat = current_user.chats.find(params[:chat_id])
    PlanGenerator.new(@chat).call
    redirect_to chat_path(@chat), notice: "Your plan was saved! 🎉"
  rescue JSON::ParserError, ActiveRecord::RecordInvalid
    redirect_to chat_path(@chat), alert: "Sorry, we couldn't save your plan. Please try again."
  end
end
