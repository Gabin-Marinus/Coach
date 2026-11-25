class AddGoalToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :goals, :string, array: true, default: []
  end
end
