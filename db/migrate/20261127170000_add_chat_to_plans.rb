class AddChatToPlans < ActiveRecord::Migration[8.1]
  # The chat a plan was made in, so it can be adjusted there later with all its context
  def up
    add_reference :plans, :chat, foreign_key: { on_delete: :nullify }

    # Existing plans: the plan chat the user wrote in last before saving the plan
    execute <<~SQL
      UPDATE plans SET chat_id = (
        SELECT messages.chat_id FROM messages
        JOIN chats ON chats.id = messages.chat_id
        WHERE chats.user_id = plans.user_id AND chats.kind = 'plan' AND messages.created_at <= plans.created_at
        ORDER BY messages.created_at DESC LIMIT 1
      )
    SQL
  end

  def down
    remove_reference :plans, :chat
  end
end
