# Saves (or updates) a plan in the background and shows its progress live in the chat (Turbo Streams),
# so the user isn't stuck on a 1-minute page load, and a slow save can't be cut off by a web request timeout.
class PlanGenerationJob < ApplicationJob
  queue_as :default

  def perform(chat, plan = nil)
    @chat = chat
    saved = PlanGenerator.new(chat, plan: plan, progress: ->(step) { show(step: step) }).call
    show(step: :done, plan: saved, updated: plan.present?)
  rescue PlanGenerator::Error, RubyLLM::Error, JSON::ParserError, ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[PlanGenerationJob] #{e.class}: #{e.message}")
    show(step: :failed)
  end

  private

  def show(**locals)
    Turbo::StreamsChannel.broadcast_replace_to(@chat, :messages, target: "plan_actions",
                                                                  partial: "chats/plan_progress",
                                                                  locals: { chat: @chat, **locals })
  end
end
