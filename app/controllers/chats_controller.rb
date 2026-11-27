class ChatsController < ApplicationController
  def index
    @chats = current_user.chats.plan_chats.order(updated_at: :desc)
  end

  def show
    @chat = current_user.chats.plan_chats.find(params[:id])
    @messages = @chat.messages.where(role: %w[user assistant]).order(:created_at)
    @message = Message.new
  end

  def create
    # Named after the plan it will make: "Plan #3" if the user already has 2 plans
    title = "Plan ##{current_user.plans.count + 1}"
    @chat = current_user.chats.plan_chats.new(title: title, model: RubyLLM.config.default_model)

    if @chat.save
      redirect_to chat_path(@chat)
    else
      redirect_to chats_path, alert: "Could not create chat"
    end
  end

  def destroy
    current_user.chats.plan_chats.find(params[:id]).destroy
    redirect_to chats_path, notice: "Chat deleted"
  end
end
