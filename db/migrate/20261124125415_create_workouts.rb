class CreateWorkouts < ActiveRecord::Migration[8.1]
  def change
    create_table :workouts do |t|
      t.references :plan, null: false, foreign_key: true
      t.date :date
      t.string :name
      t.text :description
      t.integer :duration_min
      t.string :status, default: "planned"
      t.text :note

      t.timestamps
    end
  end
end
