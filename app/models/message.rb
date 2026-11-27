class Message < ApplicationRecord
  acts_as_message
  has_many_attached :attachments
  belongs_to :chat

  # Only check user messages: RubyLLM creates the AI reply empty first, then fills it in
  validates :content, presence: true, if: -> { role == "user" }

  # The bubble the answer to this user message streams into (see ChatResponseJob)
  def answer_dom_id
    "answer_to_message_#{id}"
  end
end
