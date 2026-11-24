class MessagesController < ApplicationController
  def create
    @chat = current_user.chats.find(params[:chat_id])

    @message = Message.new(message_params)
    @message.chat = @chat
    @message.role = "user"

    if @message.save
      @chat.complete # sends the whole conversation to the AI and saves its reply
      @chat.generate_title_from_first_message

      redirect_to chat_path(@chat)
    else
      @messages = @chat.messages.where(role: %w[user assistant]).order(:created_at)
      render "chats/show", status: :unprocessable_entity
    end
  rescue RubyLLM::Error => e
    redirect_to chat_path(@chat), alert: "AI error: #{e.message}"
  end

  private

  def message_params
    params.require(:message).permit(:content)
  end
end
