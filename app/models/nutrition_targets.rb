# Daily calorie and protein targets for a user, calculated in Ruby so the numbers are right.
# The AI is not good at maths: left alone it planned ~1,350 kcal for a user who wanted to keep her weight.
# Used by the coach chat, PlanGenerator (which also scales the meals to the target) and PlanSummary.
class NutritionTargets
  # Multiplies the resting energy (BMR) to get daily needs, see User::ACTIVITY_LEVELS
  ACTIVITY_FACTORS = {
    "sedentary" => 1.2,
    "lightly_active" => 1.375,
    "moderately_active" => 1.55,
    "very_active" => 1.725
  }.freeze

  WORKOUT_MET = 5      # average effort of a strength / cardio session (MET = times the resting energy)
  DEFICIT = 400        # kcal/day to lose about 0.35 kg a week
  SURPLUS = 250        # kcal/day for a lean muscle gain
  SAME_WEIGHT_KG = 1   # a target weight this close to the current weight means "maintain"

  # weekly_workout_minutes: all sessions of the plan, incl. the user's regular ones (football, yoga...).
  # Without it, the profile's training days x session length.
  def initialize(user, weekly_workout_minutes: nil)
    @user = user
    @weekly_workout_minutes = weekly_workout_minutes
  end

  def weight
    @user.current_weight_kg&.to_f
  end

  # Mifflin-St Jeor resting energy
  def bmr
    return if weight.nil? || @user.height_cm.nil? || @user.age.nil? || @user.sex.blank?

    base = (10 * weight) + (6.25 * @user.height_cm) - (5 * @user.age)
    @user.sex == "male" ? base + 5 : base - 161
  end

  # Daily life (the profile asks how active you are OUTSIDE workouts) + the workouts themselves
  def maintenance
    factor = ACTIVITY_FACTORS[@user.activity_level]
    (bmr * factor + workout_kcal_per_day).round if bmr && factor
  end

  # Energy of the weekly workouts, spread over the 7 days: MET x 3.5 x kg / 200 = kcal per minute
  def workout_kcal_per_day
    minutes = @weekly_workout_minutes || (@user.training_days_per_week.to_i * @user.session_minutes.to_i)
    return 0 if weight.nil? || minutes.zero?

    (minutes * WORKOUT_MET * 3.5 * weight / 200 / 7).round
  end

  # :lose, :gain or :maintain. The target weight decides first (it's the user's clearest wish),
  # then the goals: "Lose fat" => lose, "Build muscle" => gain, anything else => maintain.
  def direction
    target = @user.target_weight_kg&.to_f
    if target && weight
      return :lose if target < weight - SAME_WEIGHT_KG
      return :gain if target > weight + SAME_WEIGHT_KG

      return :maintain
    end

    return :lose if @user.goals.include?("lose_fat")
    return :gain if @user.goals.include?("build_muscle")

    :maintain
  end

  # nil if the profile misses weight, height, age, sex or activity
  def calories
    return if maintenance.nil?

    case direction
    when :lose then [maintenance - DEFICIT, bmr.round].max # never below resting energy
    when :gain then maintenance + SURPLUS
    else maintenance
    end
  end

  # More protein for muscle, strength or losing fat (to keep the muscle)
  def protein_g
    return if weight.nil?

    per_kg = (@user.goals & %w[build_muscle get_stronger lose_fat]).any? || direction == :lose ? 1.6 : 1.2
    (weight * per_kg).round
  end

  def reason
    target = @user.target_weight_kg
    case direction
    when :lose then target ? "target weight #{target} kg is below current weight #{weight} kg" : "goal: lose fat"
    when :gain then target ? "target weight #{target} kg is above current weight #{weight} kg" : "goal: build muscle"
    else target ? "target weight #{target} kg = current weight: keep the weight" : "no weight goal: keep the weight"
    end
  end

  # For the AI prompts
  def to_prompt
    return "Calculated targets: unknown (profile incomplete), use sensible amounts for the user's goals." if calories.nil?

    <<~TEXT.strip
      Calculated targets (from the user's profile, use exactly these, do not calculate your own):
      - Calories: #{calories} kcal per day (maintenance #{maintenance} kcal incl. ~#{workout_kcal_per_day} kcal/day
        for the workouts; #{direction} weight, because #{reason})
      - Protein: at least #{protein_g} g per day
    TEXT
  end
end
