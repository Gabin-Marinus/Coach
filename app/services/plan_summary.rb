# Writes the "Why this plan" explanation shown at the top of a plan.
#
# The numbers (maintenance calories, deficit, pace, protein...) are calculated here in Ruby
# so they are correct; the AI only turns them into a short, friendly explanation.
class PlanSummary
  KCAL_PER_KG = 7700 # roughly the energy in 1 kg of body fat

  # Multiplies the resting energy (BMR) to get daily needs, see User::ACTIVITY_LEVELS
  ACTIVITY_FACTORS = {
    "sedentary" => 1.2,
    "lightly_active" => 1.375,
    "moderately_active" => 1.55,
    "very_active" => 1.725
  }.freeze

  PROMPT = <<~PROMPT
    You explain to a user of a fitness app what their new 3-month plan is based on.
    You get the facts about their profile and plan, and maybe the conversation where the plan was made.

    Write a short summary in Markdown, speaking to the user as "you":
    - One short opening sentence about the main goal(s).
    - Then 3 to 5 bullets, each starting with a bold label, choosing what matters for their goals:
      **Calories** (maintenance vs. planned intake, the deficit or surplus, the expected pace per week
      and, if there is a target weight, roughly when they reach it), **Protein** (grams per day and per kg
      of body weight, and why it matters for their goals), **Training** (how many sessions and why this
      fits their level, time and equipment), **Food** (diet, allergies or other preferences respected).
    - If the pace is faster than about 1% of body weight per week, say so and recommend a slower pace.

    Each bullet is one or two natural sentences that explain WHY, not a list of numbers. For example:
    "**Calories:** Your body burns about 2,100 kcal a day, so your plan gives you about 1,700 kcal. This deficit
    of ~400 kcal means losing about 0.4 kg a week, a safe pace that gets you to 65 kg around May 2027."
    or "**Protein:** About 110 g a day (1.6 g per kg) helps your muscles repair and grow after each workout."

    Rules:
    - Use ONLY the numbers in the facts. Round them sensibly (e.g. ~2,050 kcal, ~0.4 kg). Never invent numbers.
    - Say once that calorie numbers are estimates.
    - Under 130 words. No title, no closing question.
  PROMPT

  def initialize(plan, conversation: nil)
    @plan = plan
    @user = plan.user
    @conversation = conversation
  end

  # Saves and returns the summary
  def call
    question = ["## Facts", facts, ("## Conversation\n#{@conversation}" if @conversation.present?)].compact.join("\n\n")
    summary = RubyLLM.chat.with_instructions(PROMPT).ask(question).content.to_s.strip
    @plan.update!(summary: summary)
    summary
  end

  def facts
    lines = []
    lines << "- Goals: #{@plan.goal_labels.join(', ').presence || 'none'}"
    lines << "- Plan: #{@plan.timeframe} (#{@plan.total_weeks} weeks)"
    lines << "- Sex: #{@user.sex || 'unknown'}, age: #{@user.age || 'unknown'}, height: #{@user.height_cm || '?'} cm"
    lines << "- Current weight: #{weight || '?'} kg, target weight: #{@user.target_weight_kg || 'not set'} kg"
    lines << "- Activity outside workouts: #{User::ACTIVITY_LEVELS[@user.activity_level] || 'unknown'}"
    lines << "- Diet: #{User::DIET_TYPES[@user.diet_type] || 'not set'}, allergies: #{@user.allergies.join(', ').presence || 'none'}"
    lines.concat(calorie_facts)
    lines.concat(protein_facts)
    lines.concat(training_facts)
    lines.join("\n")
  end

  private

  def weight
    @user.current_weight_kg&.to_f
  end

  # Mifflin-St Jeor resting energy
  def bmr
    return if weight.nil? || @user.height_cm.nil? || @user.age.nil? || @user.sex.blank?

    base = (10 * weight) + (6.25 * @user.height_cm) - (5 * @user.age)
    @user.sex == "male" ? base + 5 : base - 161
  end

  def maintenance_kcal
    factor = ACTIVITY_FACTORS[@user.activity_level]
    (bmr * factor).round if bmr && factor
  end

  # Average per day over the first two weeks (the meals rotate every two weeks)
  def daily_average(column)
    meals = @plan.meals.where(date: @plan.start_date...(@plan.start_date + 14.days))
    days = meals.distinct.count(:date)
    return if days.zero?

    (meals.sum(column).to_f / days).round
  end

  def calorie_facts
    planned = daily_average(:calories)
    maintenance = maintenance_kcal
    lines = []
    lines << "- Estimated maintenance calories (Mifflin-St Jeor x activity): #{maintenance || 'unknown'} kcal/day"
    lines << "- Planned average intake: #{planned || 'unknown'} kcal/day"
    return lines unless planned && maintenance

    difference = planned - maintenance
    weekly_change = (difference * 7.0 / KCAL_PER_KG).round(2)
    lines << "- Daily #{difference.negative? ? 'deficit' : 'surplus'}: #{difference.abs} kcal"
    lines << "- Expected weight change: #{weekly_change} kg/week " \
             "(#{(100 * weekly_change.abs / weight).round(1)}% of body weight per week)"
    lines << "- Expected weight at end of plan: #{(weight + (weekly_change * @plan.total_weeks)).round(1)} kg"
    lines.concat(target_facts(weekly_change))
  end

  def target_facts(weekly_change)
    target = @user.target_weight_kg&.to_f
    return [] if target.nil? || weight.nil?

    to_go = (target - weight).round(1)
    return ["- Already at target weight"] if to_go.zero?

    same_direction = weekly_change.nonzero? && (to_go.negative? == weekly_change.negative?)
    return ["- The planned calories do not move the weight towards the target (#{to_go} kg to go)"] unless same_direction

    weeks = (to_go / weekly_change).ceil
    ["- Target reached in about #{weeks} weeks, around #{(@plan.start_date + weeks.weeks).strftime('%B %Y')}"]
  end

  def protein_facts
    protein = daily_average(:protein_g)
    return [] if protein.nil?

    per_kg = weight ? " (#{(protein / weight).round(1)} g per kg body weight)" : ""
    ["- Planned average protein: #{protein} g/day#{per_kg}"]
  end

  def training_facts
    first_week = @plan.workouts.where(date: @plan.week_dates(1))
    minutes = first_week.average(:duration_min)&.round
    [
      "- Training: #{first_week.count} sessions per week#{", about #{minutes} min each" if minutes} " \
      "(asked for #{@user.training_days_per_week || '?'} days, #{@user.session_minutes || '?'} min)",
      "- Fitness level: #{User::FITNESS_LEVELS[@user.fitness_level] || 'unknown'}, " \
      "location: #{User::TRAINING_LOCATIONS[@user.training_location] || 'unknown'}",
      "- Workouts in week 1: #{first_week.order(:date).pluck(:name).join(', ').presence || 'none'}"
    ]
  end
end
