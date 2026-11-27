# The floating coach button: short Q&A conversations about the user's profile and current plan
class CoachController < ApplicationController
  def show
    # Always a chat, so the panel can listen for live answers (turbo_stream_from) from the first question
    @chat = current_user.chats.coach_chats.order(:created_at).last || new_coach_chat
    @messages = @chat.messages.where(role: %w[user assistant]).where.not(content: [nil, ""]).order(:created_at)
  end

  def ask
    content = params[:content].to_s.strip.first(Chat::MAX_QUESTION_LENGTH)
    return redirect_to(coach_path) if content.blank?

    @chat = current_user.chats.coach_chats.order(:created_at).last || new_coach_chat

    if @chat.questions_left.zero?
      flash[:coach_error] = "You've reached #{Chat::MAX_COACH_QUESTIONS} questions. Start a new conversation."
      return redirect_to(coach_path)
    end

    # Saved now and shown right away; the answer streams in from the background job
    @message = @chat.ask_later(content).messages.where(role: "user").order(:id).last
    ChatResponseJob.perform_later(@chat, @message)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to coach_path }
    end
  end

  # Starts a fresh conversation (and a fresh question count)
  def reset
    new_coach_chat
    redirect_to coach_path
  end

  private

  def new_coach_chat
    current_user.chats.create!(kind: "coach", title: "Coach", model: RubyLLM.config.default_model)
  end
end
