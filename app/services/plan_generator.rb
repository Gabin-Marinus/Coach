class PlanGenerator
  # The AI's answer was unusable twice (missing meals or calories): the user is asked to try again
  class Error < StandardError; end

  WEEKS_IN_ROTATION = 2
  # Default training days (1 = first day of the plan), with rest days in between,
  # for users without regular sessions (the AI put them all at the start of the week)
  TRAINING_DAYS_SPREAD = {
    1 => [1], 2 => [1,
4], 3 => [1, 3, 5], 4 => [1, 2, 4, 6], 5 => [1, 2, 4, 5, 6], 6 => [1, 2, 3, 4, 5, 6], 7 => (1..7).to_a
  }.freeze
  DEFAULT_MEALS_PER_DAY = 3
  DEFAULT_TRAINING_DAYS = 3
  DAYS = (1..7).map { |day| "day_#{day}" }.freeze
  MAX_WEEK_INGREDIENTS = 35 # keeps the weekly shopping list short (pantry staples not counted)
  MIN_MAIN_INGREDIENTS = 4  # a lunch or dinner with fewer is missing ingredients (lasagna with only salmon and spinach)
  PANTRY_STAPLES = "oil, butter, salt, pepper, spices, dried herbs, garlic, flour, stock cubes, vinegar, soy sauce"
  CALORIE_MARGIN = 0.02     # a day within 2% of the calorie target is left as it is
  SCALE_LIMITS = (0.6..1.6) # portions are never scaled more than this
  MIN_DIFFERENT_DISHES = 12 # of the 14 lunches and dinners of a week
  MIN_PROTEIN_SHARE = 0.85  # of the protein target

  # JSON schemas for the AI's structured output: the answer is always valid JSON in this shape
  MEAL_SCHEMA = {
    type: "object",
    additionalProperties: false,
    required: %w[meal_type name description recipe calories protein_g carbs_g fat_g ingredients],
    properties: {
      meal_type: { type: "string", enum: Meal::MEAL_TYPES.keys },
      name: { type: "string" },
      description: { type: "string" },
      recipe: { type: "string" },
      calories: { type: "integer" },
      protein_g: { type: "integer" },
      carbs_g: { type: "integer" },
      fat_g: { type: "integer" },
      ingredients: { type: "array", items: Meal::INGREDIENT_SCHEMA }
    }
  }.freeze

  WORKOUT_SCHEMA = {
    type: "object",
    additionalProperties: false,
    # In the order the workout is done, so the AI plans it that way: warm-up, rounds of exercises, cool-down
    required: %w[weekday name description duration_min warm_up rounds round_rest_sec exercises cool_down],
    properties: {
      weekday: { type: "string", enum: Date::DAYNAMES }, # so regular sessions stay on their real day
      name: { type: "string" },
      description: { type: "string" },
      duration_min: { type: "integer" },
      warm_up: { type: "string" },
      rounds: { type: "integer" },          # the whole exercise list is done this many times
      round_rest_sec: { type: "integer" },  # rest after each round
      exercises: {
        type: "array", minItems: 4, maxItems: 8,
        items: {
          type: "object", additionalProperties: false,
          required: %w[name reps tip],
          properties: {
            name: { type: "string" },
            reps: { type: "string" }, # per round; a string so "10", "12 per leg" or "30 sec" all work
            tip: { type: "string" }   # one short technique cue
          }
        }
      },
      cool_down: { type: "string" }
    }
  }.freeze

  REGULAR_SESSION_SCHEMA = {
    type: "object",
    additionalProperties: false,
    required: %w[weekday name duration_min],
    properties: {
      weekday: { type: "string", enum: Date::DAYNAMES },
      name: { type: "string" },
      duration_min: { type: "integer" }
    }
  }.freeze

  def initialize(chat)
    @chat = chat
    @user = chat.user
  end

  def call
    first_week  = ask_week(first_week_prompt, workouts: true)
    @weekly_workout_minutes = first_week["workouts"].sum { |workout| workout["duration_min"].to_i }.nonzero?
    first_week = fit_to_calorie_target(first_week) # again, now that the regular sessions (football...) are known
    second_week = ask_week(second_week_prompt(first_week["meals"]), workouts: false)
    meal_weeks  = [first_week["meals"], second_week["meals"]]

    plan = ActiveRecord::Base.transaction do
      # Plan copies the user's goals automatically (before_validation in Plan)
      plan = @user.plans.create!(start_date: start_date, end_date: end_date)
      create_workouts(plan, first_week["workouts"])
      create_meals(plan, meal_weeks)
      plan
    end

    add_shopping_lists(plan)
    add_summary(plan)
    plan
  end

  private

  # "Why this plan" text; the plan is still saved if this fails (it can be generated later)
  def add_summary(plan)
    PlanSummary.new(plan, conversation: conversation).call
  rescue RubyLLM::Error, ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[PlanGenerator] Plan summary failed: #{e.class}: #{e.message}")
  end

  # Weekly shopping lists; the plan is still saved if this fails (there is a button to make them later)
  def add_shopping_lists(plan)
    ShoppingListWriter.new(plan).call
  rescue RubyLLM::Error, JSON::ParserError, ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[PlanGenerator] Shopping lists failed: #{e.class}: #{e.message}")
  end

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

        plan.workouts.create!(workout.slice("name", "description", "duration_min", "exercises",
                                             "warm_up", "rounds", "round_rest_sec", "cool_down").merge("date" => date))
      end
    end
  end

  def create_meals(plan, meal_weeks)
    each_week do |week_start, index|
      Array(meal_weeks[index % WEEKS_IN_ROTATION]).each do |meal|
        date = week_start + (meal["day"].to_i - 1).days
        next if date > end_date

        plan.meals.create!(
          meal.slice("meal_type", "name", "description", "recipe", "ingredients",
                     "calories", "protein_g", "carbs_g", "fat_g").merge("date" => date)
        )
      end
    end
  end

  # One week of meals (and workouts). The schema forces all 7 days into the answer;
  # if a day still has too few meals, the AI is asked once more.
  # Asks up to twice: keeps the first good week, else the first usable one, else gives up (Error)
  def ask_week(prompt, workouts:)
    attempts = []
    2.times do
      week = parse_week(ask(prompt, workouts: workouts))
      next unless usable?(week) && (!workouts || enough_workouts?(week))

      place_workouts(week)
      fit_to_calorie_target(week)
      return week if good?(week)

      attempts << week
      Rails.logger.warn("[PlanGenerator] Week not varied enough, missing ingredients or too little protein, asking again")
    end
    attempts.first || raise(Error, "The AI's week of meals was unusable twice")
  end

  # After scaling: varied lunches and dinners with all their ingredients, and enough protein
  # (the AI sometimes alternated the same 2 dishes all week, or left out the milk, onions, pasta...)
  def good?(week)
    dishes = week["meals"].select { |meal| %w[lunch dinner].include?(meal["meal_type"]) }
    protein_per_day = week["meals"].sum { |meal| meal["protein_g"].to_i } / 7.0
    dishes.map { |meal| meal["name"].to_s.downcase.strip }.uniq.size >= MIN_DIFFERENT_DISHES &&
      dishes.all? { |meal| Array(meal["ingredients"]).size >= MIN_MAIN_INGREDIENTS } &&
      (targets.protein_g.nil? || protein_per_day >= targets.protein_g * MIN_PROTEIN_SHARE)
  end

  # Every day has its meals, and its calories are close enough to the target to be scaled
  def usable?(week)
    meals_by_day = week["meals"].group_by { |meal| meal["day"] }
    target = targets.calories
    (1..7).all? do |day|
      meals = meals_by_day[day].to_a
      total = meals.sum { |meal| meal["calories"].to_i }
      meals.size >= meals_per_day && total.positive? && (target.nil? || SCALE_LIMITS.cover?(target.to_f / total))
    end
  end

  # Regular sessions + new workouts = the user's training days
  def enough_workouts?(week)
    regular, new_workouts = week["workouts"].partition { |workout| workout["regular"] }
    new_workouts.size >= new_workouts_needed(regular.size)
  end

  # Calorie and protein targets; the workouts count once week 1 is known (see #call)
  def targets
    @user.nutrition_targets(weekly_workout_minutes: @weekly_workout_minutes)
  end

  # "Tuesday" => the plan's day number of that weekday (day 1 is the start date)
  def place_workouts(week)
    spread_new_workouts(week["workouts"])
    week["workouts"].each do |workout|
      weekday = Date::DAYNAMES.index(workout["weekday"]) || start_date.wday
      workout["day"] = ((weekday - start_date.wday) % 7) + 1
    end
  end

  # The AI put a new workout on Friday, right before Saturday boxing: a new workout next to another session
  # moves to the free weekday with the most rest around it (Tuesday or Wednesday). Regular sessions never move.
  def spread_new_workouts(workouts)
    workouts.reject { |workout| workout["regular"] }.each do |workout|
      others = (workouts - [workout]).filter_map { |other| Date::DAYNAMES.index(other["weekday"]) }
      free_days = (0..6).to_a - others
      next if others.empty? || free_days.empty?

      current_rest = rest_around(Date::DAYNAMES.index(workout["weekday"]), others)
      next if current_rest >= 2 # already a rest day on both sides: the AI's day is kept

      best = free_days.max_by { |day| rest_around(day, others) }
      workout["weekday"] = Date::DAYNAMES[best] if rest_around(best, others) > current_rest
    end
  end

  # Days between this weekday and the closest other session, around the week (Sunday is next to Monday)
  # (0 if the day is unknown or already taken)
  def rest_around(day, others)
    return 0 if day.nil? || others.include?(day)

    others.map { |other| [(day - other) % 7, (other - day) % 7].min }.min
  end

  def default_training_weekdays
    TRAINING_DAYS_SPREAD.fetch(training_days, [1]).map { |day| (start_date + (day - 1)).strftime("%A") }.to_sentence
  end

  # The AI's days are often too small or too big (it planned ~1,350 kcal for someone needing ~1,700).
  # Each day's portions are scaled to the calculated target: calories, macros and ingredient amounts.
  def fit_to_calorie_target(week)
    target = targets.calories
    return week if target.nil?

    week["meals"].group_by { |meal| meal["day"] }.each_value do |day_meals|
      total = day_meals.sum { |meal| meal["calories"].to_i }
      next if total.zero? || (total - target).abs <= target * CALORIE_MARGIN

      factor = (target.to_f / total).clamp(SCALE_LIMITS)
      day_meals.each { |meal| scale_meal(meal, factor) }
    end
    week
  end

  def scale_meal(meal, factor)
    %w[calories protein_g carbs_g fat_g].each { |key| meal[key] = (meal[key].to_i * factor).round }
    Array(meal["ingredients"]).each do |ingredient|
      ingredient["quantity"] = (ingredient["quantity"] * factor).round(1) if ingredient["quantity"].is_a?(Numeric)
    end
  end

  # effort: :low = the AI "thinks" less before answering. Saving a plan was ~4 minutes,
  # mostly hidden thinking; filling in a plan that is already agreed doesn't need much.
  def ask(prompt, workouts:)
    RubyLLM.chat.with_instructions(prompt).with_thinking(effort: :low)
           .with_schema(week_schema(workouts: workouts)).ask(conversation).parsed
  end

  def week_schema(workouts:)
    meals_of_a_day = { type: "array", items: MEAL_SCHEMA, minItems: meals_per_day, maxItems: meals_per_day }
    properties = {}
    if workouts
      # Written first: the sessions the user already does every week (profile and chat), then the new
      # workouts to reach the profile's training days in total (checked in #usable?, trimmed in #parse_week)
      properties[:regular_sessions] = { type: "array", items: REGULAR_SESSION_SCHEMA, maxItems: 7 }
      properties[:workouts] = { type: "array", items: WORKOUT_SCHEMA, maxItems: training_days }
    end
    # Before the meals, so the AI plans a short shopping list and varied dishes first
    properties[:week_ingredients] = { type: "array", items: { type: "string" }, maxItems: MAX_WEEK_INGREDIENTS }
    properties[:lunch_and_dinner_dishes] = { type: "array", items: { type: "string" }, minItems: 14, maxItems: 14 }
    properties[:days] = {
      type: "object",
      additionalProperties: false,
      required: DAYS,
      properties: DAYS.to_h { |day| [day, meals_of_a_day] }
    }

    {
      name: "week_plan",
      strict: true,
      schema: { type: "object", additionalProperties: false, required: properties.keys.map(&:to_s),
properties: properties }
    }
  end

  # { "days" => { "day_1" => [meals], ... } } => { "workouts" => [...], "meals" => [{ "day" => 1, ... }] }
  # The user's regular sessions (football, yoga...) become workouts of the plan too
  def parse_week(answer)
    meals = DAYS.each_with_index.flat_map do |day, index|
      Array(answer.dig("days", day)).map { |meal| meal.merge("day" => index + 1) }
    end
    regular = Array(answer["regular_sessions"]).map do |session|
      session.merge("description" => "Your regular weekly session: it's part of your plan, keep it up!",
                    "exercises" => [], "regular" => true)
    end
    # The regular sessions count in the user's training days: only the missing ones are new workouts
    new_workouts = Array(answer["workouts"]).first(new_workouts_needed(regular.size))
    { "workouts" => regular + new_workouts, "meals" => meals }
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

  # 2 training days with boxing on Saturday => 1 new workout
  def new_workouts_needed(regular_count)
    [training_days - regular_count, 0].max
  end

  # The most important rules come first: with low thinking effort the AI follows the top of the list best
  def meal_rules
    <<~RULES
      Most important:
      - #{targets.to_prompt.gsub("\n", "\n  ")}
        Every day must add up to the calorie target (portions for one person).
      - #{@user.seasonal_food_rule(start_date, end_date)}
      #{budget_rule}
      - Simple, everyday food: standard, well-known recipes that are easy to cook (e.g. omelette,
        overnight oats, chili, stir-fry, pasta with sauce, tray bake, soup, wraps, curry with rice).
        Only common supermarket ingredients: no niche grains or specialty products (e.g. no farro,
        freekeh, teff, amaranth, tahini, miso).
      - Short shopping list: at most #{MAX_WEEK_INGREDIENTS} different ingredients in the whole week (not counting
        pantry staples: #{PANTRY_STAPLES}). Reuse the same ingredients in several meals (e.g. one bag of spinach
        for an omelette, a pasta and a curry; one pack of chicken for two dinners; milk for the oats and a béchamel).
        Never leave out an ingredient a dish needs to stay under this limit: choose simpler dishes instead.
      - Time-saving forms are welcome: frozen berries, frozen vegetable mixes, canned beans and tomatoes,
        pre-washed salad, microwave rice pouches.
      - Respect the user's diet, allergies, food dislikes and cooking time. Include the favourite meals
        from the user's profile and the dishes and foods the user said in the conversation they like or
        usually cook (fitted to the calorie target), each favourite once or twice a week, not every day.
      - Vary the base: at most 2 lunches or dinners per week with the same base (pasta, rice, potatoes,
        bread, quinoa...).

      Structure:
      - Every day has exactly #{meals_per_day} meals.
      - Lunches and dinners are all different kinds of dishes (e.g. a curry, a pasta, a soup, wraps, a chili,
        a tray bake, an omelette, a stir-fry): not the same bowl or salad again with small changes.
        Use at most 3 different breakfasts and 2 different snacks in the week, repeated on several days.
      - meal_type is one of: #{Meal::MEAL_TYPES.keys.join(', ')}.
      - Descriptions are one sentence. Recipes are 3 to 5 short steps that name each ingredient with its amount
        (e.g. "Fry 1 chopped onion and 1 garlic clove in 1 tsp oil, add 1 tbsp curry paste and 200 g canned
        tomatoes...") and explain any sauce (e.g. béchamel: melt 10 g butter, stir in 10 g flour, whisk in 150 ml milk).

      #{Meal::INGREDIENT_RULES}
    RULES
  end

  def budget_rule
    return "- Keep the meals affordable, using cheap everyday staples." if @user.weekly_food_budget.nil?

    "- Budget: all the meals of the week together must cost at most #{@user.weekly_food_budget} " \
      "#{@user.currency} in groceries, at realistic local prices."
  end

  def answer_format
    <<~FORMAT
      Answer format:
      - First "week_ingredients": the at most #{MAX_WEEK_INGREDIENTS} ingredients you will cook with this week
        (not counting pantry staples), seasonal for the user's country (see the rules above), with everything
        the dishes need (milk, onions, the pasta or lasagna sheets...). Then use only these and pantry staples
        in the meals, and list every one a meal uses in its "ingredients".
      - Then "lunch_and_dinner_dishes": the 14 lunches and dinners of the week, 14 DIFFERENT dishes
        (each favourite of the user at most twice, at most 2 with the same base like pasta or rice).
      - Then "days" has day_1 to day_7 (day_1 is the first day of the plan). Each day has
        exactly #{meals_per_day} meals: breakfast, lunch and dinner#{', plus snacks' if meals_per_day > 3},
        using the dishes listed above, each once. Every day reaches the protein target.
    FORMAT
  end

  def first_week_prompt
    <<~PROMPT
      You convert a coaching conversation into a structured weekly plan.
      Use the LAST plan the assistant proposed in the conversation and the user profile below.
      The week starts on #{start_date.strftime('%A')}.

      #{@user.coach_context}

      Workout rules:
      - The user trains #{training_days} days per week IN TOTAL. Their regular sessions count in this number.
      - "regular_sessions": the sessions the user already does on their own every week, from "Regular sessions"
        in the profile and from the conversation (e.g. boxing on Saturday, a football match on Tuesday), on
        their usual weekday, with their real length. Only sessions the app doesn't need to plan. Empty if none.
      - "workouts": the NEW workouts the app plans: #{training_days} minus the number of regular sessions
        (e.g. #{training_days} training days and 1 regular session = #{[training_days - 1, 0].max} new workouts;
        none if the regular sessions already fill the training days). On other days than the regular sessions,
        with rest days in between. Without regular sessions, use #{default_training_weekdays}.
      - If the user described the format of a session or asked the app to fill part of it (e.g. "I run 20 min and
        then do exercises you suggest"), it is one of the NEW workouts, built exactly that way: put the run in
        "warm_up" (e.g. "20 min easy run"), then a strength circuit, and count the run in "duration_min".
        Never replace it with another kind of session (no HIIT instead of the run). It is not a regular session.
      - Spread the sessions over the week: at least one rest day between two sessions when possible
        (e.g. boxing on Saturday + 1 new workout => Tuesday or Wednesday, not Friday or Sunday).
      - New workouts follow the plan proposed in the conversation and respect the user's session length, equipment, training location, injuries and exercise dislikes.
      - Each new workout is a circuit: "warm_up" (done once, e.g. "5 min brisk walk + arm circles"),
        then "rounds" of ALL "exercises" one after the other, with "round_rest_sec" rest after each round,
        then "cool_down" (done once). Exercises are only the main moves (no warm-up or stretches in the list),
        each with reps or time per round and one short technique tip.
        Match the user's fitness level (beginner: 2-3 rounds, simple moves; intermediate: 3-4 rounds),
        goals (strength: 6-10 reps; muscle: 8-12; endurance: 15+ or 30-45 sec) and session length.
      - Each workout is shown to the user: "name" is a short title without the word "new" (e.g. "Full body strength A"),
        "description" one sentence about its focus (e.g. "Legs and back, with a short core finisher").
        Exercise "name" is only the exercise (e.g. "Goblet squat"): the reps go in their own field.

      Meal rules:
      #{meal_rules}
      #{answer_format}
    PROMPT
  end

  def second_week_prompt(first_week_meals)
    used_meals = Array(first_week_meals).select { |meal| %w[lunch dinner].include?(meal["meal_type"]) }
                                        .map { |meal| meal["name"] }.join(", ")
    used_ingredients = Array(first_week_meals).flat_map { |meal| Array(meal["ingredients"]) }
                                              .filter_map { |ingredient| ingredient["name"] if ingredient.is_a?(Hash) }
                                              .uniq.join(", ")

    <<~PROMPT
      You create the SECOND week of meals for an existing nutrition plan.
      Follow the plan the assistant proposed in the conversation and the user profile below.

      #{@user.coach_context}

      Meal rules:
      #{meal_rules}
      - Do NOT repeat any of these lunches or dinners from the first week: #{used_meals}
      - Mostly reuse these first-week ingredients, so the shopping stays short and familiar: #{used_ingredients}

      #{answer_format}
    PROMPT
  end
end
