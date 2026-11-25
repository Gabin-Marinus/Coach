class AddKindToChats < ActiveRecord::Migration[8.1]
  def change
    # "plan" = chat that builds a plan, "coach" = questions from the coach button
    add_column :chats, :kind, :string, default: "plan", null: false
  end
end
