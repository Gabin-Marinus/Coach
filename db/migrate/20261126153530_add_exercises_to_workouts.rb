class AddExercisesToWorkouts < ActiveRecord::Migration[8.1]
  def change
    # [{ "name" => "Goblet squat", "sets" => 3, "reps" => "10-12", "rest_sec" => 60, "tip" => "Knees over toes" }]
    add_column :workouts, :exercises, :jsonb, default: [], null: false
  end
end
