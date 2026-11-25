class AddSummaryToPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :plans, :summary, :text
  end
end
