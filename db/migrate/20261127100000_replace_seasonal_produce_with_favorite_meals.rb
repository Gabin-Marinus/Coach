class ReplaceSeasonalProduceWithFavoriteMeals < ActiveRecord::Migration[8.1]
  def change
    # The AI-made seasonal produce list is replaced by the seasonal food rule in the prompts
    remove_column :users, :seasonal_produce, :jsonb, default: {}, null: false
    remove_column :users, :seasonal_produce_key, :string

    # Dishes the user loves: the meal plan includes them once or twice a week
    add_column :users, :favorite_meals, :text
  end
end
