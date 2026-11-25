class MessagesController < ApplicationController
  def create
    @chat = current_user.chats.find(params[:chat_id])
    content = message_params[:content]

    if content.blank?
      redirect_to chat_path(@chat), alert: "Please write a message first."
      return
    end

    @chat.with_instructions(@chat.instructions)
    @chat.ask(content)
    @chat.generate_title_from_first_message

    redirect_to chat_path(@chat)
  rescue RubyLLM::Error
    redirect_to chat_path(@chat), alert: "Your coach is unavailable right now. Please try again."
  end

  private

  def message_params
    params.require(:message).permit(:content)
  end
end
