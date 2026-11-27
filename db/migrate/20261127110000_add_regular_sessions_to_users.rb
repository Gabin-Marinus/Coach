class AddRegularSessionsToUsers < ActiveRecord::Migration[8.1]
  def change
    # Sessions the user already does every week (e.g. "boxing on Saturday, 60 min"): part of the plan
    add_column :users, :regular_sessions, :text
  end
end
