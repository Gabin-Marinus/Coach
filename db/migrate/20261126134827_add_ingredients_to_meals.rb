class AddIngredientsToMeals < ActiveRecord::Migration[8.1]
  def change
    # [{ "name" => "rolled oats", "quantity" => 60, "unit" => "g", "category" => "Bread & grains" }, ...]
    add_column :meals, :ingredients, :jsonb, default: [], null: false
  end
end
