class CreateMeals < ActiveRecord::Migration[8.1]
  def change
    create_table :meals do |t|
      t.references :plan, null: false, foreign_key: true
      t.date :date
      t.string :meal_type
      t.string :name
      t.text :description
      t.text :recipe
      t.integer :calories
      t.integer :protein_g
      t.integer :carbs_g
      t.integer :fat_g
      t.string :status, default: "planned"
      t.text :note

      t.timestamps
    end
  end
end
