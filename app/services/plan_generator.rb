class PlanGenerator
  WEEKS_IN_ROTATION = 2
  DEFAULT_MEALS_PER_DAY = 3
  DEFAULT_TRAINING_DAYS = 3

  def initialize(chat)
    @chat = chat
    @user = chat.user
  end

  def call
    first_week  = ask_json(first_week_prompt)
    second_week = ask_json(second_week_prompt(first_week["meals"]))
    meal_weeks  = [first_week["meals"], second_week["meals"]]

    ActiveRecord::Base.transaction do
      # Plan copies the user's goals automatically (before_validation in Plan)
      plan = @user.plans.create!(start_date: start_date, end_date: end_date)
      create_workouts(plan, first_week["workouts"])
      create_meals(plan, meal_weeks)
      plan
    end
  end

  private

  def start_date
    Date.today
  end

  def end_date
    start_date + Plan::DURATION - 1.day
  end

  # Yields the first day of every week of the plan, with the week index (0, 1, 2...)
  def each_week
    week_start = start_date
    index = 0

    while week_start <= end_date
      yield week_start, index
      week_start += 1.week
      index += 1
    end
  end

  def create_workouts(plan, workouts)
    each_week do |week_start, _index|
      Array(workouts).each do |workout|
        date = week_start + (workout["day"].to_i - 1).days
        next if date > end_date

        plan.workouts.create!(workout.slice("name", "description", "duration_min").merge("date" => date))
      end
    end
  end

  def create_meals(plan, meal_weeks)
    each_week do |week_start, index|
      Array(meal_weeks[index % WEEKS_IN_ROTATION]).each do |meal|
        date = week_start + (meal["day"].to_i - 1).days
        next if date > end_date

        plan.meals.create!(
          meal.slice("meal_type", "name", "description", "recipe",
                     "calories", "protein_g", "carbs_g", "fat_g").merge("date" => date)
        )
      end
    end
  end

  def ask_json(prompt)
    text = RubyLLM.chat.with_instructions(prompt).ask(conversation).content
    JSON.parse(text.gsub(/```(json)?/, "").strip)
  end

  def conversation
    @chat.messages
         .where(role: %w[user assistant])
         .order(:created_at)
         .map { |message| "#{message.role.upcase}: #{message.content}" }
         .join("\n\n")
  end

  def meals_per_day
    @user.meals_per_day || DEFAULT_MEALS_PER_DAY
  end

  def training_days
    @user.training_days_per_week || DEFAULT_TRAINING_DAYS
  end

  def meal_rules
    <<~RULES
      - Days are numbered 1 to 7. Day 1 is the first day of the plan.
      - Every day from 1 to 7 has exactly #{meals_per_day} meals.
      - All meals of the week are different: never repeat a meal.
      - meal_type is one of: #{Meal::MEAL_TYPES.keys.join(', ')}.
      - Respect the user's diet, allergies, food dislikes and cooking time.
      - Keep descriptions to one sentence and recipes to at most 3 short steps.
    RULES
  end

  def meal_format
    <<~FORMAT
      { "day": 1, "meal_type": "breakfast", "name": "string", "description": "string",
        "recipe": "string", "calories": 500, "protein_g": 30, "carbs_g": 50, "fat_g": 15 }
    FORMAT
  end

  def first_week_prompt
    <<~PROMPT
      You convert a coaching conversation into a structured weekly plan.
      Use the LAST plan the assistant proposed in the conversation and the user profile below.

      #{@user.coach_context}

      Workout rules:
      - Exactly #{training_days} training days in the week. Rest days have no workout.
      - Respect the user's session length, equipment, training location, injuries and exercise dislikes.

      Meal rules:
      #{meal_rules}
      Return ONLY valid JSON, with no text before or after, in exactly this format:
      {
        "workouts": [
          { "day": 1, "name": "string", "description": "string", "duration_min": 45 }
        ],
        "meals": [
          #{meal_format}
        ]
      }
    PROMPT
  end

  def second_week_prompt(first_week_meals)
    used_meals = Array(first_week_meals).map { |meal| meal["name"] }.join(", ")

    <<~PROMPT
      You create the SECOND week of meals for an existing nutrition plan.
      Follow the plan the assistant proposed in the conversation and the user profile below.

      #{@user.coach_context}

      Meal rules:
      #{meal_rules}
      - Do NOT repeat any of these meals from the first week: #{used_meals}

      Return ONLY valid JSON, with no text before or after, in exactly this format:
      {
        "meals": [
          #{meal_format}
        ]
      }
    PROMPT
  end
end
