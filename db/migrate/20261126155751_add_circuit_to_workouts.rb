class AddCircuitToWorkouts < ActiveRecord::Migration[8.1]
  # A workout is a circuit: warm-up once, then all exercises one after the other, repeated "rounds" times,
  # then cool-down once
  def change
    add_column :workouts, :rounds, :integer          # 3 = do the whole exercise list 3 times
    add_column :workouts, :round_rest_sec, :integer  # rest after each round
    add_column :workouts, :warm_up, :string          # done once, before the rounds
    add_column :workouts, :cool_down, :string        # done once, after the rounds
  end
end
