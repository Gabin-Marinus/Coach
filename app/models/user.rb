class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # ---------- Associations ----------
  has_many :plans, dependent: :destroy
  has_many :workouts, through: :plans
  has_many :meals, through: :plans
  has_many :chats, dependent: :destroy

  # ---------- Dropdowns (one answer) ----------
  SEXES = {
    "female" => "Female",
    "male" => "Male"
  }.freeze

  GOALS = {
    "lose_fat" => "Lose weight / body fat",
    "build_muscle" => "Build muscle",
    "maintain" => "Maintain my weight",
    "get_stronger" => "Get stronger",
    "improve_endurance" => "Improve endurance / cardio fitness",
    "improve_mobility" => "Improve flexibility and mobility",
    "general_health" => "Feel healthier overall"
  }.freeze

  ACTIVITY_LEVELS = {
    "sedentary" => "Mostly sitting (desk job, little walking)",
    "lightly_active" => "Lightly active (some walking)",
    "moderately_active" => "Moderately active (on my feet a lot)",
    "very_active" => "Very active (physical job)"
  }.freeze

  DIET_TYPES = {
    "omnivore" => "No restrictions",
    "vegetarian" => "Vegetarian",
    "vegan" => "Vegan",
    "pescatarian" => "Pescatarian",
    "low_carb" => "Low carb",
    "mediterranean" => "Mediterranean",
    "halal" => "Halal",
    "kosher" => "Kosher"
  }.freeze

  COOKING_TIMES = {
    "quick" => "Quick (under 15 min)",
    "medium" => "Medium (15 to 30 min)",
    "long" => "I enjoy cooking (30+ min)"
  }.freeze

  FITNESS_LEVELS = {
    "beginner" => "Beginner (new or coming back after a break)",
    "intermediate" => "Intermediate (train regularly)",
    "advanced" => "Advanced (train consistently for 1+ years)"
  }.freeze

  TRAINING_LOCATIONS = {
    "home" => "At home",
    "gym" => "At the gym",
    "outdoors" => "Outdoors",
    "mixed" => "A mix"
  }.freeze

  PREFERRED_TIMES = {
    "morning" => "Morning",
    "midday" => "Midday",
    "evening" => "Evening",
    "flexible" => "It varies"
  }.freeze

  # Country dropdown (names, as the AI reads them in the prompts)
  COUNTRIES = YAML.load_file(Rails.root.join("config/countries.yml")).freeze

  BUDGET_PERIODS = {
    "week" => "per week",
    "month" => "per month"
  }.freeze

  CURRENCIES = {
    "EUR" => "€ Euro",
    "USD" => "$ US dollar",
    "GBP" => "£ British pound",
    "CHF" => "CHF Swiss franc",
    "CAD" => "$ Canadian dollar",
    "AUD" => "$ Australian dollar",
    "BRL" => "R$ Brazilian real",
    "MXN" => "$ Mexican peso",
    "JPY" => "¥ Japanese yen",
    "INR" => "₹ Indian rupee",
    "ZAR" => "R South African rand"
  }.freeze

  MEALS_PER_DAY = [2, 3, 4, 5].freeze
  TRAINING_DAYS = (1..7).to_a.freeze
  SESSION_MINUTES = [15, 20, 30, 45, 60, 90].freeze

  # ---------- Checkboxes (several answers) ----------
  ALLERGIES = {
    "gluten" => "Gluten",
    "dairy" => "Dairy",
    "eggs" => "Eggs",
    "peanuts" => "Peanuts",
    "tree_nuts" => "Tree nuts",
    "soy" => "Soy",
    "fish" => "Fish",
    "shellfish" => "Shellfish",
    "sesame" => "Sesame"
  }.freeze

  EXERCISE_TYPES = {
    "strength" => "Strength training / weights",
    "bodyweight" => "Bodyweight / calisthenics",
    "hiit" => "HIIT",
    "running" => "Running",
    "cycling" => "Cycling",
    "swimming" => "Swimming",
    "walking" => "Walking / hiking",
    "yoga" => "Yoga",
    "pilates" => "Pilates",
    "mobility" => "Stretching / mobility",
    "dance" => "Dance",
    "team_sports" => "Team sports",
    "boxing" => "Boxing / martial arts"
  }.freeze

  EQUIPMENT = {
    "none" => "No equipment",
    "dumbbells" => "Dumbbells",
    "kettlebells" => "Kettlebells",
    "resistance_bands" => "Resistance bands",
    "pull_up_bar" => "Pull-up bar",
    "bench" => "Bench",
    "barbell" => "Barbell and rack",
    "machines" => "Gym machines",
    "cardio_machine" => "Treadmill / bike / rower",
    "yoga_mat" => "Yoga mat",
    "jump_rope" => "Jump rope"
  }.freeze

  INJURIES = {
    "knees" => "Knees",
    "lower_back" => "Lower back",
    "shoulders" => "Shoulders",
    "wrists" => "Wrists",
    "ankles" => "Ankles",
    "hips" => "Hips",
    "neck" => "Neck"
  }.freeze

  ARRAY_FIELDS = {
    allergies: ALLERGIES,
    exercise_types: EXERCISE_TYPES,
    equipment: EQUIPMENT,
    injuries: INJURIES,
    goals: GOALS
  }.freeze

  # ---------- Validations ----------
  # allow_blank: users sign up with email + password first,
  # and fill in the profile afterwards
  validates :sex, inclusion: { in: SEXES.keys }, allow_blank: true
  validates :activity_level, inclusion: { in: ACTIVITY_LEVELS.keys }, allow_blank: true
  validates :diet_type, inclusion: { in: DIET_TYPES.keys }, allow_blank: true
  validates :cooking_time, inclusion: { in: COOKING_TIMES.keys }, allow_blank: true
  validates :fitness_level, inclusion: { in: FITNESS_LEVELS.keys }, allow_blank: true
  validates :training_location, inclusion: { in: TRAINING_LOCATIONS.keys }, allow_blank: true
  validates :preferred_time, inclusion: { in: PREFERRED_TIMES.keys }, allow_blank: true
  validates :meals_per_day, inclusion: { in: MEALS_PER_DAY }, allow_blank: true
  validates :training_days_per_week, inclusion: { in: TRAINING_DAYS }, allow_blank: true
  validates :session_minutes, inclusion: { in: SESSION_MINUTES }, allow_blank: true
  validates :height_cm, numericality: { in: 100..250 }, allow_blank: true
  validates :current_weight_kg, numericality: { in: 30..300 }, allow_blank: true
  validates :target_weight_kg, numericality: { in: 30..300 }, allow_blank: true
  validates :food_budget, numericality: { greater_than: 0, less_than: 1_000_000 }, allow_blank: true
  validates :food_budget_period, inclusion: { in: BUDGET_PERIODS.keys }, allow_blank: true
  validates :currency, inclusion: { in: CURRENCIES.keys }, allow_blank: true
  validates :country, inclusion: { in: COUNTRIES }, allow_blank: true
  validates :city, length: { maximum: 100 }
  validates :favorite_meals, length: { maximum: 500 }
  normalizes :city, :country, with: ->(value) { value.strip.presence }

  before_validation :clean_array_fields
  before_validation :set_equipment_from_location
  validate :array_fields_have_valid_options

  # Only checked when saving the profile form
  with_options on: :profile do
    validates :birth_date, :sex, :height_cm, :current_weight_kg,
              :activity_level, :diet_type, :meals_per_day, :cooking_time,
              :fitness_level, :training_location, :goals,
              :training_days_per_week, :session_minutes,
              :country, :food_budget, :food_budget_period, :currency, presence: true
  end

  # ---------- Methods ----------
  def profile_complete?
    birth_date.present? && sex.present? && height_cm.present? &&
      current_weight_kg.present? && activity_level.present? && fitness_level.present?
  end

  def age
    return nil if birth_date.blank?

    ((Date.today - birth_date) / 365.25).floor
  end

  def current_plan
    plans.active.last
  end
  # added by Pri

  def coach_context
    [profile_context, plans_context].join("\n\n")
  end

  def nutrition_targets(weekly_workout_minutes: nil)
    NutritionTargets.new(self, weekly_workout_minutes: weekly_workout_minutes)
  end

  def ready_for_plan?
    profile_complete? && goals.present? && country.present? && food_budget_text.present?
  end

  # "Lyon, France"
  def location
    [city, country].compact_blank.join(", ").presence
  end

  # "60 EUR per week"
  def food_budget_text
    return if food_budget.blank? || currency.blank?

    "#{food_budget.to_f.round(2).to_s.delete_suffix('.0')} #{currency} #{BUDGET_PERIODS.fetch(food_budget_period,
                                                                                              'per week')}"
  end

  # Budget for one week, so the AI can check a 7-day meal plan against it
  def weekly_food_budget
    return if food_budget.blank?

    food_budget_period == "month" ? (food_budget * 12 / 52).round : food_budget.round
  end

  # Rule for the AI prompts: meals with local, seasonal food (no mango in a European winter)
  def seasonal_food_rule(from = Date.today, to = from + Plan::DURATION)
    months = (from..to).map { |date| date.strftime("%B") }.uniq.to_sentence

    if country.present?
      "Seasonal, local food (important): the user lives in #{country}, the meals are for #{months}. " \
        "Only use fruit and vegetables that are in season in #{country} in those months, or stored or frozen " \
        "local produce (e.g. apples, frozen berries). Never use produce that is out of season there or imported " \
        "from far away. Example for a Northern European winter: use apples, pears, citrus, cabbage, kale, leeks, " \
        "carrots, beetroot, pumpkin and potatoes; avoid mango, pineapple, papaya, asparagus, fresh berries, " \
        "eggplant and bell peppers. Seasons are reversed in the southern hemisphere. " \
        "Use ingredients that are easy to find and affordable in supermarkets in #{country}."
    else
      "The user's country is not informed: use common ingredients sold in most supermarkets " \
        "and avoid tropical or exotic fruit (e.g. mango, pineapple, papaya)."
    end
  end

  private

  def profile_context
    <<~TEXT
      ## User profile
      - Today's date: #{Date.today.strftime('%-d %B %Y')}
      - Location: #{location || 'not informed'}
      - Food budget: #{budget_context}
      - Goals: #{labels(GOALS, goals)}
      - Age: #{age || 'not informed'}
      - Sex: #{label(SEXES, sex)}
      - Height: #{height_cm ? "#{height_cm} cm" : 'not informed'}
      - Current weight: #{current_weight_kg ? "#{current_weight_kg} kg" : 'not informed'}
      - Target weight: #{target_weight_kg ? "#{target_weight_kg} kg" : 'not informed'}
      - Activity level: #{label(ACTIVITY_LEVELS, activity_level)}
      - Diet: #{label(DIET_TYPES, diet_type)}
      - Allergies: #{labels(ALLERGIES, allergies)}
      - Food dislikes: #{food_dislikes.presence || 'none'}
      - Favourite meals: #{favorite_meals.presence || 'none'}
      - Meals per day: #{meals_per_day || 'not informed'}
      - Cooking time: #{label(COOKING_TIMES, cooking_time)}
      - Fitness level: #{label(FITNESS_LEVELS, fitness_level)}
      - Preferred exercise: #{labels(EXERCISE_TYPES, exercise_types)}
      - Equipment: #{labels(EQUIPMENT, equipment)}
      - Training location: #{label(TRAINING_LOCATIONS, training_location)}
      - Training days per week: #{training_days_per_week || 'not informed'}
      - Session length: #{session_minutes ? "#{session_minutes} min" : 'not informed'}
      - Preferred time: #{label(PREFERRED_TIMES, preferred_time)}
      - Injuries: #{labels(INJURIES, injuries)}
      - Injury notes: #{injury_notes.presence || 'none'}
      - Exercise dislikes: #{exercise_dislikes.presence || 'none'}
    TEXT
  end

  def plans_context
    return "## Previous plans\nThe user has no plans yet. This will be their first plan." if plans.empty?

    summaries = plans.order(start_date: :desc).limit(3).map do |plan|
      workouts = plan.workouts.group(:status).count
      meals    = plan.meals.group(:status).count

      <<~TEXT
        ### #{plan.goal_labels.join(', ')} (#{plan.status})
        - Period: #{plan.start_date} to #{plan.end_date}
        - Workouts: #{workouts['done'] || 0} done, #{workouts['skipped'] || 0} skipped, #{workouts['planned'] || 0} planned
        - Meals: #{meals['done'] || 0} done, #{meals['skipped'] || 0} skipped, #{meals['planned'] || 0} planned
      TEXT
    end

    "## Previous plans (most recent first)\n#{summaries.join("\n")}"
  end

  def budget_context
    return "not informed" if food_budget_text.nil?
    return food_budget_text if food_budget_period != "month"

    "#{food_budget_text} (about #{weekly_food_budget} #{currency} per week)"
  end

  def label(options, key)
    options[key] || "not informed"
  end

  def labels(options, keys)
    keys.map { |key| options[key] }.compact.join(", ").presence || "none"
  end

  # Checkbox forms send an empty "" value, so remove it
  def clean_array_fields
    ARRAY_FIELDS.each_key do |field|
      self[field] = Array(self[field]).compact_blank
    end
  end

  # We don't ask gym users about equipment, we assume they have everything
  def set_equipment_from_location
    self.equipment = EQUIPMENT.keys - ["none"] if training_location == "gym"
  end

  def array_fields_have_valid_options
    ARRAY_FIELDS.each do |field, options|
      invalid = self[field] - options.keys
      errors.add(field, "has invalid options: #{invalid.join(', ')}") if invalid.any?
    end
  end
end
