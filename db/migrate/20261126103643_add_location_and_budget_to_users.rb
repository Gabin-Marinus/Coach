class AddLocationAndBudgetToUsers < ActiveRecord::Migration[8.1]
  def change
    # Location: used to suggest local, seasonal produce
    add_column :users, :city, :string
    add_column :users, :country, :string

    # Food budget: the meal plan has to fit in it
    add_column :users, :food_budget, :decimal, precision: 8, scale: 2
    add_column :users, :food_budget_period, :string
    add_column :users, :currency, :string
  end
end
