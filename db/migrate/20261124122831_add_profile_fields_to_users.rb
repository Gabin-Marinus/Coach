class AddProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :birth_date, :date
    add_column :users, :sex, :string
    add_column :users, :height_cm, :integer
    add_column :users, :current_weight_kg, :decimal, precision: 5, scale: 1
    add_column :users, :activity_level, :string
    add_column :users, :target_weight_kg, :decimal, precision: 5, scale: 1
    add_column :users, :diet_type, :string
    add_column :users, :allergies, :string, array: true, default: []
    add_column :users, :food_dislikes, :text
    add_column :users, :meals_per_day, :integer
    add_column :users, :cooking_time, :string
    add_column :users, :fitness_level, :string
    add_column :users, :exercise_types, :string, array: true, default: []
    add_column :users, :equipment, :string, array: true, default: []
    add_column :users, :training_location, :string
    add_column :users, :training_days_per_week, :integer
    add_column :users, :session_minutes, :integer
    add_column :users, :preferred_time, :string
    add_column :users, :injuries, :string, array: true, default: []
    add_column :users, :injury_notes, :text
    add_column :users, :exercise_dislikes, :text
  end
end
