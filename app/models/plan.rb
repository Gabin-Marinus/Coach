class Plan < ApplicationRecord
  belongs_to :user
  has_many :workouts, dependent: :destroy
  has_many :meals, dependent: :destroy

  STATUSES = %w[active archived].freeze
  DURATION = 1.month

  # Take the user's current goals if none were given
  before_validation { self.goals = user.goals if goals.blank? && user }

  validates :goals, presence: true
  validate :goals_are_valid
  validates :status, inclusion: { in: STATUSES }
  validates :start_date, :end_date, presence: true
  validate :end_date_after_start_date

  scope :active, -> { where(status: "active") }

  after_create :archive_previous_plans

  def goal_labels
    goals.map { |g| User::GOALS[g] }
  end

  # 1 for the user's first plan, 2 for the second...
  def number
    user.plans.where(created_at: ..created_at).count
  end

  # "Plan #1"
  def title
    "Plan ##{number}"
  end

  # "Nov 25, 2026 – Feb 24, 2027"
  def timeframe
    "#{start_date.strftime('%b %-d, %Y')} – #{end_date.strftime('%b %-d, %Y')}"
  end

  def ended?
    end_date < Date.today
  end

  def total_weeks
    ((end_date - start_date).to_i / 7) + 1
  end

  def current_week
    (((Date.today - start_date).to_i / 7) + 1).clamp(1, total_weeks)
  end

  def week_dates(number)
    first_day = start_date + (number - 1).weeks
    first_day..[first_day + 6.days, end_date].min
  end

  # Week number of a date: 1 for the first 7 days of the plan...
  def week_of(date)
    (((date - start_date).to_i / 7) + 1).clamp(1, total_weeks)
  end

  def shopping_list(week)
    ShoppingList.new(self, week)
  end

  # Details of this plan for the coach: progress, this week, and today in full
  def coach_context(today = Date.today)
    week = week_dates(current_week)
    week_workouts = workouts.where(date: week).order(:date).group_by(&:date)
    week_meals = meals.where(date: week).order(:date).group_by(&:date)

    days = week.map do |date|
      day_workouts = week_workouts[date] || []
      day_meals = (week_meals[date] || []).sort_by { |m| Meal::MEAL_TYPES.keys.index(m.meal_type) || 99 }
      coach_day(date, day_workouts, day_meals, full: date == today)
    end

    <<~TEXT
      ## Current plan: #{title} (#{timeframe})
      - Today: #{today.strftime('%A, %b %-d, %Y')}, week #{current_week} of #{total_weeks}
      - Goals: #{goal_labels.join(', ').presence || 'none'}
      - Progress so far: #{coach_progress(workouts, 'workouts')}; #{coach_progress(meals, 'meals')}

      ### Why this plan (shown to the user)
      #{summary.presence || 'No summary yet.'}

      ### This week
      #{days.join("\n")}
    TEXT
  end

  private

  def coach_progress(records, name)
    counts = records.where(date: ..Date.today).group(:status).count
    "#{name} #{counts['done'] || 0} done, #{counts['skipped'] || 0} skipped, #{counts['planned'] || 0} not marked"
  end

  def coach_day(date, day_workouts, day_meals, full:)
    lines = ["#### #{date.strftime('%a %b %-d')}#{' (today)' if full}"]
    if day_workouts.empty?
      lines << "- Workout: rest day"
    else
      day_workouts.each do |w|
        lines << "- Workout: #{w.name} (#{w.duration_min || '?'} min) [#{w.status}]"
        lines << "  #{w.description}" if full && w.description.present?
        w.exercise_lines.each { |line| lines << "  - #{line}" } if full
      end
    end
    day_meals.each do |m|
      lines << "- #{Meal::MEAL_TYPES[m.meal_type]}: #{m.name} (#{m.calories} kcal, P #{m.protein_g} g, " \
               "C #{m.carbs_g} g, F #{m.fat_g} g) [#{m.status}]"
      lines << "  Recipe: #{m.recipe}" if full && m.recipe.present?
    end
    lines.join("\n")
  end

  def goals_are_valid
    invalid = goals - User::GOALS.keys
    errors.add(:goals, "has invalid options: #{invalid.join(', ')}") if invalid.any?
  end

  def end_date_after_start_date
    return if start_date.blank? || end_date.blank?

    errors.add(:end_date, "must be after the start date") if end_date < start_date
  end

  def archive_previous_plans
    user.plans.active.where.not(id: id).update_all(status: "archived")
  end
end
