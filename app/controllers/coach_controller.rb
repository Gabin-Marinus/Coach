# The floating coach button: short Q&A conversations about the user's profile and current plan
class CoachController < ApplicationController
  def show
    @chat = current_user.chats.coach_chats.order(:created_at).last
    @messages = @chat ? @chat.messages.where(role: %w[user assistant]).where.not(content: [nil, ""]).order(:created_at) : []
  end

  def ask
    content = params[:content].to_s.strip.first(Chat::MAX_QUESTION_LENGTH)
    return redirect_to(coach_path) if content.blank?

    chat = current_user.chats.coach_chats.order(:created_at).last || new_coach_chat

    if chat.questions_left.zero?
      flash[:coach_error] = "You've reached #{Chat::MAX_COACH_QUESTIONS} questions. Start a new conversation."
    else
      chat.with_instructions(chat.instructions)
      chat.ask(content)
    end

    redirect_to coach_path
  rescue RubyLLM::Error
    flash[:coach_error] = "Your coach is unavailable right now. Please try again."
    redirect_to coach_path
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
