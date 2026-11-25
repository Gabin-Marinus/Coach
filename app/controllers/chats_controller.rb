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
    @chat = current_user.chats.plan_chats.new(title: Chat::DEFAULT_TITLE, model: RubyLLM.config.default_model)

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
