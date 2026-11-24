class ChangeGoalToGoalsOnPlans < ActiveRecord::Migration[8.1]
  def change
    remove_column :plans, :goal, :string
    add_column :plans, :goals, :string, array: true, default: []
  end
end
