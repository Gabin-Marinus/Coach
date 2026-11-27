# Gets the coach's answer in the background and streams it to the page bit by bit (Turbo Streams over
# ActionCable). Used by the plan chat and the coach panel: the user's message is already saved (ask_later)
# and the page shows a "typing" bubble (messages/_pending) that this job fills.
class ChatResponseJob < ApplicationJob
  queue_as :default

  BROADCAST_EVERY = 0.1 # seconds: the page is updated at most 10 times a second, not for every word
  ERROR = "Your coach is unavailable right now. Please try again.".freeze

  def perform(chat, question)
    @chat = chat
    @target = question.answer_dom_id
    @content = +""

    chat.with_instructions(chat.instructions)
    chat.complete { |chunk| stream(chunk.content) }
    show(@chat.messages.where(role: "assistant").order(:id).last&.content.presence || @content)
  rescue RubyLLM::Error => e
    Rails.logger.warn("[ChatResponseJob] #{e.class}: #{e.message}")
    broadcast(:update, target: @target, partial: "messages/error", locals: { error: ERROR })
  ensure
    unlock_form
  end

  private

  def stream(text)
    return if text.blank?

    @content << text
    return if @shown_at && Time.current - @shown_at < BROADCAST_EVERY

    show(@content)
    @shown_at = Time.current
  end

  # The text so far, as Markdown, in the answer's bubble
  def show(content)
    broadcast(:update, target: @target, partial: "messages/answer_body", locals: { chat: @chat, content: content })
  end

  # The form works again; plus the "Save my plan" button (plan chat) or the question count (coach panel)
  def unlock_form
    if @chat.coach?
      broadcast(:replace, target: "coach_footer", partial: "coach/footer", locals: { chat: @chat.reload })
    else
      broadcast(:replace, target: "new_message_container", partial: "chats/form", locals: { chat: @chat })
      broadcast(:replace, target: "plan_actions", partial: "chats/plan_actions", locals: { chat: @chat })
    end
  end

  def broadcast(action, **)
    Turbo::StreamsChannel.public_send(:"broadcast_#{action}_to", @chat, :messages, **)
  end
end
