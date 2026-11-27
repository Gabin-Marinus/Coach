# Turns a coaching conversation into a saved plan: workouts, 2 weeks of meals that repeat, shopping lists, summary.
#
# To be fast, the AI calls that don't depend on each other run at the same time (see #call):
#   1. own sessions (boxing...) + the menu (names of all dishes)           ~5 s
#   2. workouts + week 1 meals + week 2 meals                               ~20 s
#   3. only if needed: ingredients of meals that came back incomplete      ~5 s
#   4. save, then shopping lists + summary                                  ~15 s
# Only the AI calls run in threads: the database is used before and after them.
class PlanGenerator
  # The AI's answer was unusable twice (missing meals or exercises): the user is asked to try again
  class Error < StandardError; end

  # The steps shown to the user while the plan is made (see PlanGenerationJob)
  STEPS = {
    reading: "Reading your conversation",
    cooking: "Planning your workouts and 2 weeks of meals",
    saving: "Saving your plan",
    finishing: "Writing your shopping lists and summary"
  }.freeze

  WEEKS_IN_ROTATION = 2
  # Default training days (1 = first day of the plan), with rest days in between,
  # for users without regular sessions (the AI put them all at the start of the week)
  TRAINING_DAYS_SPREAD = {
    1 => [1], 2 => [1,
                    4], 3 => [1, 3, 5], 4 => [1, 2, 4, 6], 5 => [1, 2, 4, 5, 6], 6 => [1, 2, 3, 4, 5, 6], 7 => (1..7).to_a
  }.freeze
  DEFAULT_MEALS_PER_DAY = 3
  DEFAULT_TRAINING_DAYS = 3
  MAX_WEEK_INGREDIENTS = 35 # keeps the weekly shopping list short (pantry staples not counted)
  MIN_MAIN_INGREDIENTS = 4  # a lunch or dinner with fewer is missing ingredients (lasagna with only salmon and spinach)
  PANTRY_STAPLES = "oil, butter, salt, pepper, spices, dried herbs, garlic, flour, stock cubes, vinegar, soy sauce"
  CALORIE_MARGIN = 0.02     # a day within 2% of the calorie target is left as it is
  SCALE_LIMITS = (0.6..1.6) # portions are never scaled more than this
  BREAKFAST_OPTIONS = 3     # different breakfasts, rotating over the days (written once, placed by Ruby)
  SNACK_OPTIONS = 2
  # The meals of a day, by the user's meals per day
  DAY_SLOTS = {
    2 => %w[lunch dinner],
    3 => %w[breakfast lunch dinner],
    4 => %w[breakfast lunch snack dinner],
    5 => %w[breakfast snack lunch snack dinner]
  }.freeze

  # JSON schemas for the AI's structured output: the answer is always valid JSON in this shape
  # (meal_type is set by Ruby from the meal's place in the day)
  MEAL_SCHEMA = {
    type: "object",
    additionalProperties: false,
    required: %w[name description recipe calories protein_g carbs_g fat_g ingredients],
    properties: {
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
    required: %w[weekday name description duration_min warm_up cardio rounds round_rest_sec exercises cool_down],
    properties: {
      weekday: { type: "string", enum: Date::DAYNAMES }, # so regular sessions stay on their real day
      name: { type: "string" },
      description: { type: "string" },
      duration_min: { type: "integer" },
      warm_up: { type: "string" },
      cardio: { type: "string" },           # before the circuit, e.g. "20 min easy run"; "" if none
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

  # Sessions the user does on their own every week (boxing class, football...): they count in the training days.
  # Asked in a separate, small AI call, so the week's answer has an exact number of new workouts to plan
  # (in one big answer the AI sometimes counted "run 20 min, then exercises you suggest" as the user's own).
  OWN_SESSIONS_SCHEMA = {
    name: "own_sessions",
    strict: true,
    schema: {
      type: "object",
      additionalProperties: false,
      required: %w[own_sessions],
      properties: {
        own_sessions: {
          type: "array", maxItems: 7,
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[weekday name duration_min],
            properties: {
              weekday: { type: "string", enum: Date::DAYNAMES },
              name: { type: "string" },
              duration_min: { type: "integer" }
            }
          }
        }
      }
    }
  }.freeze

  # Names only: all the dishes of the 2 weeks, so both weeks can be written at the same time without repeats
  MENU_PROMPT = <<~PROMPT
    You choose the menu of a 2-week meal plan for a fitness app, following the plan the assistant
    proposed in the conversation and the user's profile. Give only dish names (e.g. "Chickpea curry with rice").
    - "breakfasts" and "snacks": simple options that repeat over the days.
    - "week_1_dishes" and "week_2_dishes": 14 lunches and dinners each, all 28 DIFFERENT dishes and different
      kinds of dishes (a curry, a pasta, a soup, wraps, a chili, a tray bake, an omelette, a stir-fry...),
      at most 2 per week with the same base (pasta, rice, potatoes, bread...).
    - Include the user's favourite meals (profile and conversation), each once or twice per week.
    - Simple, everyday recipes with common, seasonal, affordable supermarket ingredients, reused across the week.
    - Respect the user's diet, allergies, food dislikes and cooking time.
  PROMPT

  OWN_SESSIONS_PROMPT = <<~PROMPT
    From the user's profile ("Regular sessions") and the coaching conversation, list the sessions the user
    does COMPLETELY ON THEIR OWN every week: a class, a sport, a match, a club training (e.g. boxing on Saturday,
    football on Tuesday, a yoga class). Use the weekday and length from the LAST plan the assistant proposed.
    Do NOT list a session where the app plans any exercises: "I run 20 min and then do exercises you suggest",
    a strength circuit, a gym workout from the plan. The app plans those, so they are not the user's own.
    Empty list if there are none.
  PROMPT

  # plan: an existing plan to rebuild from the chat ("Update Plan #2"): same number and dates, new content.
  # progress: called with each step of STEPS as it starts, so the page can show it (see PlanGenerationJob)
  def initialize(chat, plan: nil, progress: nil)
    @chat = chat
    @user = chat.user
    @plan = plan
    @progress = progress || ->(_step) {}
  end

  def call
    @progress.call(:reading)
    @context = @user.coach_context # read once: every prompt uses it
    @conversation = conversation
    @own_sessions, @menu = parallel(-> { ask_own_sessions }, -> { ask_menu })

    @progress.call(:cooking)
    @workout_minutes = estimated_workout_minutes # for the calorie target in the meal prompts
    prompts = [workouts_prompt, meals_prompt(1), meals_prompt(2)] # built here: they read the database
    workouts, week1, week2 = parallel(-> { ask_workouts(prompts[0]) }, -> { ask_meals(1, prompts[1]) },
                                        -> { ask_meals(2, prompts[2]) })
    @workout_minutes = workouts.sum { |workout| workout["duration_min"].to_i }.nonzero? # the real ones
    weeks = complete_ingredients([week1, week2]).map { |week| fit_to_calorie_target(week) }

    @progress.call(:saving)
    plan = ActiveRecord::Base.transaction do
      plan = save_plan
      create_workouts(plan, workouts)
      create_meals(plan, weeks)
      plan
    end

    @progress.call(:finishing)
    add_shopping_lists_and_summary(plan)
    plan
  end

  private

  # Runs AI calls at the same time and returns their answers in the same order. An error in one is raised here.
  # permit_concurrent_loads: the waiting thread lets the others load Rails classes (no deadlock in development)
  def parallel(*calls)
    threads = calls.map { |call| Thread.new { Rails.application.executor.wrap { call.call } } }
    ActiveSupport::Dependencies.interlock.permit_concurrent_loads { threads.map(&:value) }
  end

  # ---------- 1. Own sessions and menu ----------

  # [{ "weekday" => "Saturday", "name" => "Boxing", "duration_min" => 60 }] (see OWN_SESSIONS_PROMPT)
  def ask_own_sessions
    answer = RubyLLM.chat.with_instructions(OWN_SESSIONS_PROMPT).with_thinking(effort: :low)
                    .with_schema(OWN_SESSIONS_SCHEMA).ask(question).parsed
    Array(answer["own_sessions"]).first(training_days)
  rescue RubyLLM::Error => e
    Rails.logger.warn("[PlanGenerator] Own sessions failed, planning all training days: #{e.message}")
    []
  end

  def ask_menu
    RubyLLM.chat.with_instructions(MENU_PROMPT).with_thinking(effort: :low).with_schema(menu_schema).ask(question).parsed
  end

  def menu_schema
    names = ->(count) { { type: "array", items: { type: "string" }, minItems: count, maxItems: count } }
    properties = { breakfasts: names.call(breakfasts? ? BREAKFAST_OPTIONS : 0), snacks: names.call(snacks? ? SNACK_OPTIONS : 0),
                   week_1_dishes: names.call(14), week_2_dishes: names.call(14) }
    { name: "menu", strict: true,
      schema: { type: "object", additionalProperties: false, required: properties.keys.map(&:to_s), properties: properties } }
  end

  def question
    "#{@context}\n\nConversation:\n#{@conversation}"
  end

  def own_sessions
    @own_sessions || []
  end

  # ---------- 2. Workouts and meals ----------

  # The user's own sessions (boxing...) without exercises, then the workouts the app plans
  def ask_workouts(prompt)
    own = own_sessions.map do |session|
      session.merge("description" => "Your regular weekly session: it's part of your plan, keep it up!",
                    "exercises" => [], "regular" => true)
    end
    return place_workouts(own) if new_workouts_needed.zero?

    2.times do
      planned = Array(ask_ai(prompt, workouts_schema)["workouts"])
      return place_workouts(own + planned) if planned.size >= new_workouts_needed &&
                                              planned.all? { |workout| Array(workout["exercises"]).size >= 4 }

      Rails.logger.warn("[PlanGenerator] Workouts without exercises, asking again")
    end
    raise Error, "The AI's workouts were unusable twice"
  end

  def workouts_schema
    count = new_workouts_needed
    { name: "workouts", strict: true,
      schema: { type: "object", additionalProperties: false, required: %w[workouts],
                properties: { workouts: { type: "array", items: WORKOUT_SCHEMA, minItems: count, maxItems: count } } } }
  end

  # One week of meals: week 1 also writes the breakfasts and snacks, which week 2 reuses.
  # Asked again once if a day can't reach the calorie target.
  def ask_meals(week, prompt)
    2.times do
      answer = ask_ai(prompt, meals_schema(week))
      return answer if answer["lunches_and_dinners"].to_a.size == 14

      Rails.logger.warn("[PlanGenerator] Week #{week} meals incomplete, asking again")
    end
    raise Error, "The AI's week #{week} of meals was unusable twice"
  end

  def meals_schema(week)
    meals = ->(count) { { type: "array", items: MEAL_SCHEMA, minItems: count, maxItems: count } }
    properties = { week_ingredients: { type: "array", items: { type: "string" }, maxItems: MAX_WEEK_INGREDIENTS } }
    if week == 1
      properties[:breakfasts] = meals.call(breakfasts? ? BREAKFAST_OPTIONS : 0)
      properties[:snacks] = meals.call(snacks? ? SNACK_OPTIONS : 0)
    end
    properties[:lunches_and_dinners] = meals.call(14)
    { name: "week_#{week}_meals", strict: true,
      schema: { type: "object", additionalProperties: false, required: properties.keys.map(&:to_s), properties: properties } }
  end

  # effort: :low = the AI "thinks" less before answering; filling in a plan that is already agreed doesn't need much
  def ask_ai(prompt, schema)
    RubyLLM.chat.with_instructions(prompt).with_thinking(effort: :low).with_schema(schema).ask(@conversation).parsed
  end

  def breakfasts?
    day_slots.include?("breakfast")
  end

  def snacks?
    day_slots.include?("snack")
  end

  def day_slots
    DAY_SLOTS.fetch(meals_per_day, DAY_SLOTS[DEFAULT_MEALS_PER_DAY])
  end

  # ---------- 3. From the AI's answers to days ----------

  # [answer of week 1, answer of week 2] => [{ "meals" => [{ "day" => 1, "meal_type" => "breakfast", ... }] }, ...]
  # Breakfasts and snacks (from week 1) rotate over the days; lunches and dinners come in order (day 1 lunch,
  # day 1 dinner, day 2 lunch...). Each meal is its own copy, so scaling one day doesn't change another.
  def build_weeks(answers)
    breakfasts = Array(answers.first["breakfasts"])
    snacks = Array(answers.first["snacks"])
    answers.map do |answer|
      mains = Array(answer["lunches_and_dinners"])
      snack_index = -1
      meals = (1..7).flat_map do |day|
        day_slots.map do |slot|
          meal = case slot
                 when "breakfast" then breakfasts[(day - 1) % breakfasts.size] if breakfasts.any?
                 when "snack" then snacks[(snack_index += 1) % snacks.size] if snacks.any?
                 else mains[((day - 1) * 2) + (slot == "dinner" ? 1 : 0)]
                 end
          meal&.deep_dup&.merge("day" => day, "meal_type" => slot)
        end
      end
      { "meals" => meals.compact }
    end
  end

  # Meals the AI wrote with too few ingredients (a lasagna with only salmon and spinach) are completed in one
  # small call, instead of asking for whole weeks again
  def complete_ingredients(answers)
    weeks = build_weeks(answers)
    incomplete = weeks.flat_map { |week| week["meals"] }.select { |meal| missing_ingredients?(meal) }
                      .uniq { |meal| meal["name"] }
    return weeks if incomplete.empty?

    lists = MealIngredients.ingredients_for(incomplete).zip(incomplete).to_h { |list, meal| [meal["name"], list] }
    weeks.each do |week|
      week["meals"].each do |meal|
        list = lists[meal["name"]]
        meal["ingredients"] = list if list.present? && list.size > Array(meal["ingredients"]).size
      end
    end
  rescue RubyLLM::Error => e
    Rails.logger.warn("[PlanGenerator] Completing ingredients failed: #{e.message}")
    weeks
  end

  def missing_ingredients?(meal)
    minimum = %w[lunch dinner].include?(meal["meal_type"]) ? MIN_MAIN_INGREDIENTS : 2
    Array(meal["ingredients"]).size < minimum
  end

  # ---------- 4. Saving ----------

  # A new plan (it copies the user's goals, see Plan), or the plan being updated, emptied first
  def save_plan
    return @user.plans.create!(chat: @chat, start_date: start_date, end_date: end_date) if @plan.nil?

    @plan.workouts.delete_all
    @plan.meals.delete_all
    @plan.update!(goals: @user.goals, chat: @chat, summary: nil, shopping_lists: {})
    @plan
  end

  # Shopping lists and the "Why this plan" summary at the same time. The plan is saved even if they fail:
  # the plan page has buttons to make them later.
  def add_shopping_lists_and_summary(plan)
    summary = PlanSummary.new(plan, conversation: @conversation)
    question = summary.question
    summary_thread = Thread.new { Rails.application.executor.wrap { PlanSummary.ask(question) } }

    begin
      ShoppingListWriter.new(plan).call
    rescue RubyLLM::Error, JSON::ParserError, ActiveRecord::RecordInvalid => e
      Rails.logger.warn("[PlanGenerator] Shopping lists failed: #{e.class}: #{e.message}")
    end

    text = ActiveSupport::Dependencies.interlock.permit_concurrent_loads { summary_thread.value }
    summary.save(text)
  rescue RubyLLM::Error, ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[PlanGenerator] Plan summary failed: #{e.class}: #{e.message}")
  end

  # An updated plan keeps its dates, so it stays the same month (and "Plan #2")
  def start_date
    @plan&.start_date || Date.today
  end

  def end_date
    @plan&.end_date || (start_date + Plan::DURATION - 1.day)
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
                                             "warm_up", "cardio", "rounds", "round_rest_sec", "cool_down").merge("date" => date))
      end
    end
  end

  def create_meals(plan, weeks)
    each_week do |week_start, index|
      Array(weeks[index % WEEKS_IN_ROTATION]["meals"]).each do |meal|
        date = week_start + (meal["day"].to_i - 1).days
        next if date > end_date

        plan.meals.create!(
          meal.slice("meal_type", "name", "description", "recipe", "ingredients",
                     "calories", "protein_g", "carbs_g", "fat_g").merge("date" => date)
        )
      end
    end
  end

  # ---------- Calories ----------

  # Calorie and protein targets, counting the week's workouts (incl. boxing...)
  def targets
    @user.nutrition_targets(weekly_workout_minutes: @workout_minutes)
  end

  # Before the workouts are written: the own sessions + the planned ones at the profile's session length
  def estimated_workout_minutes
    own = own_sessions.sum { |session| session["duration_min"].to_i }
    (own + (new_workouts_needed * (@user.session_minutes || 45))).nonzero?
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

  # ---------- Workout days ----------

  # "Tuesday" => the plan's day number of that weekday (day 1 is the start date)
  def place_workouts(workouts)
    spread_new_workouts(workouts)
    workouts.each do |workout|
      weekday = Date::DAYNAMES.index(workout["weekday"]) || start_date.wday
      workout["day"] = ((weekday - start_date.wday) % 7) + 1
    end
    workouts
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

  def own_sessions_rule
    return "The user has no sessions of their own: the app plans all of them." if own_sessions.empty?

    list = own_sessions.map { |session| "#{session['name']} on #{session['weekday']}" }.to_sentence
    "The user already does #{list} on their own: these are in the plan already, do not plan them again."
  end

  def default_training_weekdays
    TRAINING_DAYS_SPREAD.fetch(training_days, [1]).map { |day| (start_date + (day - 1)).strftime("%A") }.to_sentence
  end

  # ---------- Profile ----------

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
  def new_workouts_needed
    [training_days - own_sessions.size, 0].max
  end

  # ---------- Prompts ----------

  def workouts_prompt
    <<~PROMPT
      You convert a coaching conversation into the user's weekly workouts.
      Use the LAST plan the assistant proposed in the conversation and the user profile below.
      The week starts on #{start_date.strftime('%A')}.

      #{@context}

      Workout rules:
      - The user trains #{training_days} days per week IN TOTAL. #{own_sessions_rule}
      - "workouts": exactly #{new_workouts_needed} NEW workouts that the app plans, each with warm-up, rounds and
        exercises, on other days than the user's own sessions, with rest days in between.
        #{own_sessions.empty? ? "Use #{default_training_weekdays}, unless the conversation chose other days." : ''}
      - If the user described the format of a session or asked the app to fill part of it (e.g. "I run 20 min and
        then do exercises you suggest"), it is one of the NEW workouts, built exactly that way: the run goes in
        "cardio" (e.g. "20 min easy run", done after the warm-up), then the strength circuit, and "duration_min"
        counts both (e.g. 20 min run + 25 min circuit = 45 min).
        Never replace it with another kind of session (no HIIT instead of the run).
      - Spread the sessions over the week: at least one rest day between two sessions when possible
        (e.g. boxing on Saturday + 1 new workout => Tuesday or Wednesday, not Friday or Sunday).
      - New workouts follow the plan proposed in the conversation and respect the user's session length,
        equipment, training location, injuries and exercise dislikes.
      - Each new workout is a circuit: "warm_up" (done once, e.g. "5 min brisk walk + arm circles"),
        then "cardio" if the session has any (e.g. "20 min easy run"; "" otherwise), then "rounds" of ALL
        "exercises" one after the other, with "round_rest_sec" rest after each round,
        then "cool_down" (done once). Exercises are only the main moves (no warm-up or stretches in the list),
        each with reps or time per round and one short technique tip.
        Match the user's fitness level (beginner: 2-3 rounds, simple moves; intermediate: 3-4 rounds),
        goals (strength: 6-10 reps; muscle: 8-12; endurance: 15+ or 30-45 sec) and session length.
      - Each workout is shown to the user: "name" is a short title without the word "new" or a weekday
        (e.g. "Run + full body strength"), "description" one sentence about its focus
        (e.g. "Legs and back, with a short core finisher").
        Exercise "name" is only the exercise (e.g. "Goblet squat"): the reps go in their own field.
    PROMPT
  end

  def meals_prompt(week)
    dishes = Array(@menu["week_#{week}_dishes"])
    breakfast_rule = if week == 1 && breakfasts?
                       "- \"breakfasts\": these #{BREAKFAST_OPTIONS} breakfasts, each written once (they rotate over " \
                         "the days): #{Array(@menu['breakfasts']).join(', ')}."
                     end
    snack_rule = if week == 1 && snacks?
                   "- \"snacks\": these #{SNACK_OPTIONS} snacks, each written once: #{Array(@menu['snacks']).join(', ')}."
                 end

    <<~PROMPT
      You write week #{week} of the meal plan agreed in the conversation, for the user profile below.

      #{@context}

      Meal rules:
      #{meal_rules}

      Answer format:
      - First "week_ingredients": the at most #{MAX_WEEK_INGREDIENTS} ingredients you will cook with this week
        (not counting pantry staples), seasonal for the user's country, with everything the dishes need
        (milk, onions, the pasta or lasagna sheets...). Then list every one a meal uses in its "ingredients".
      #{breakfast_rule}
      #{snack_rule}
      - "lunches_and_dinners": exactly these 14 dishes, in this order (day 1 lunch, day 1 dinner, day 2 lunch,
        day 2 dinner...): #{dishes.each_with_index.map { |dish, index| "#{index + 1}. #{dish}" }.join('; ')}.
      - Each day (#{day_slots.join(', ')}) adds up to the calorie target and reaches the protein target.
    PROMPT
  end

  # The most important rules come first: with low thinking effort the AI follows the top of the list best
  def meal_rules
    <<~RULES
      Most important:
      - #{targets.to_prompt.gsub("\n", "\n  ")}
        Every day must add up to the calorie target (portions for one person).
      - #{@user.seasonal_food_rule(start_date, end_date)}
      #{budget_rule}
      - Simple, everyday food with only common supermarket ingredients: no niche grains or specialty products
        (e.g. no farro, freekeh, teff, amaranth, tahini, miso).
      - Short shopping list: at most #{MAX_WEEK_INGREDIENTS} different ingredients in the whole week (not counting
        pantry staples: #{PANTRY_STAPLES}). Reuse the same ingredients in several meals (e.g. one bag of spinach
        for an omelette, a pasta and a curry; one pack of chicken for two dinners; milk for the oats and a béchamel).
        Never leave out an ingredient a dish needs to stay under this limit.
      - Time-saving forms are welcome: frozen berries, frozen vegetable mixes, canned beans and tomatoes,
        pre-washed salad, microwave rice pouches.
      - Respect the user's diet, allergies, food dislikes and cooking time.
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
end
