class AddCardioToWorkouts < ActiveRecord::Migration[8.1]
  def change
    # Cardio done before the circuit, e.g. "20 min easy run" (empty for most workouts)
    add_column :workouts, :cardio, :string
  end
end
