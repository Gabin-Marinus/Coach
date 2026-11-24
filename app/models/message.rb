class Message < ApplicationRecord
  acts_as_message
  has_many_attached :attachments
  belongs_to :chat

  # Only check user messages: RubyLLM creates the AI reply empty first, then fills it in
  validates :content, presence: true, if: -> { role == "user" }
end
