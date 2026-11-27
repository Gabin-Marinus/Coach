class MessagesController < ApplicationController
  def create
    @chat = current_user.chats.plan_chats.find(params[:chat_id])
    content = message_params[:content].to_s.strip
    return redirect_to(chat_path(@chat), alert: "Please write a message first.") if content.blank?

    # Saved now and shown right away; the answer streams in from the background job
    @message = @chat.ask_later(content).messages.where(role: "user").order(:id).last
    ChatResponseJob.perform_later(@chat, @message)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to chat_path(@chat) }
    end
  end

  private

  def message_params
    params.require(:message).permit(:content)
  end
end
