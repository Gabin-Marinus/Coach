class AddShoppingListsToPlans < ActiveRecord::Migration[8.1]
  def change
    # One list per week of meals (the meals repeat every 2 weeks), see ShoppingListWriter:
    # { "1" => { "items" => [{ "name" => "Bananas", "buy" => "10", "category" => "...", "tip" => nil }],
    #            "pantry" => ["olive oil", "salt"] }, "2" => {...} }
    add_column :plans, :shopping_lists, :jsonb, default: {}, null: false
  end
end
