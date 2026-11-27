class AddSeasonalProduceToUsers < ActiveRecord::Migration[8.1]
  def change
    # List of local, in-season fruits and vegetables, made by the AI
    add_column :users, :seasonal_produce, :jsonb, default: {}, null: false
    # "2026-11 antwerpen, belgium": we refresh the list when the month or location changes
    add_column :users, :seasonal_produce_key, :string
  end
end
