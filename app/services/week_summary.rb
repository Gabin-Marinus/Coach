# Nutrition numbers for one week of a plan, used by the "This week's meals" page.
# Targets are the meals the coach planned for each day; "eaten" means meals marked as done.
class WeekSummary
  MACROS = %i[calories protein_g carbs_g fat_g].freeze
  TOLERANCE = 0.1 # within 10% of the target counts as on track

  Day = Struct.new(:date, :meals) do
    def eaten
      meals.select(&:done?)
    end

    def planned_total(macro)
      meals.sum { |meal| meal.public_send(macro).to_i }
    end

    def eaten_total(macro)
      eaten.sum { |meal| meal.public_send(macro).to_i }
    end

    def meals_of_type(type)
      meals.select { |meal| meal.meal_type == type }
    end

    def today?
      date == Date.today
    end

    def past?
      date < Date.today
    end

    def upcoming?
      date > Date.today
    end

    # :low / :high once a day is over (today can only be :high, it isn't finished yet)
    def status(macro)
      target = planned_total(macro)
      return nil if target.zero? || upcoming?

      eaten_value = eaten_total(macro)
      return :high if eaten_value > target * (1 + TOLERANCE)
      return :low if past? && eaten_value < target * (1 - TOLERANCE)

      nil
    end
  end

  attr_reader :days

  def initialize(plan, dates)
    meals_by_date = plan.meals.where(date: dates).group_by(&:date)
    @days = dates.map { |date| Day.new(date, Meal.in_day_order(meals_by_date[date] || [])) }
  end

  def first_date = days.first.date
  def last_date = days.last.date

  # Finished days are the ones we can judge
  def finished_days
    days.select(&:past?)
  end

  def started?
    days.any? { |day| !day.upcoming? }
  end

  def average_eaten(macro)
    average(finished_days.map { |day| day.eaten_total(macro) })
  end

  def average_target(macro)
    average(finished_days.map { |day| day.planned_total(macro) })
  end

  def protein_low_days
    finished_days.select { |day| day.status(:protein_g) == :low }
  end

  def meals_due
    days.reject(&:upcoming?).flat_map(&:meals)
  end

  def meals_logged
    meals_due.count(&:done?)
  end

  def skipped_meals
    meals_due.count { |meal| meal.status == "skipped" }
  end

  # Past meals still marked as planned
  def unlogged_past_meals
    finished_days.flat_map(&:meals).count { |meal| meal.status == "planned" }
  end

  # Short notes for the "Weekly review" card: { tone: :good/:low/:high, title:, body: }
  def review
    return [{ tone: :good, title: "This week hasn't started yet",
              body: "Your review fills in as you log meals during the week." }] unless started?
    return [{ tone: :good, title: "Your week starts today",
              body: "Mark meals as eaten on the home page and your review will build up day by day." }] if finished_days.empty?

    [calorie_note, protein_note, skipped_note, logging_note]
  end

  private

  def average(values)
    values.empty? ? nil : (values.sum.to_f / values.size).round
  end

  def calorie_note
    eaten = average_eaten(:calories)
    target = average_target(:calories)
    body = "#{fmt(eaten)} kcal a day on average vs #{fmt(target)} kcal planned."

    if target.to_i.zero?
      { tone: :good, title: "No calorie targets yet", body: "Your plan has no calories set for these days." }
    elsif eaten > target * (1 + TOLERANCE)
      { tone: :high, title: "Calories are above plan", body: body }
    elsif eaten < target * (1 - TOLERANCE)
      { tone: :low, title: "Calories are below plan", body: "#{body} Logging every meal keeps this accurate." }
    else
      { tone: :good, title: "Calories are on track", body: body }
    end
  end

  def protein_note
    low_days = protein_low_days
    if low_days.empty?
      { tone: :good, title: "Protein target hit", body: "You reached your planned protein on every finished day." }
    else
      names = low_days.map { |day| day.date.strftime("%a") }.to_sentence
      { tone: :low, title: "Protein low on #{names}",
        body: "Try not to skip protein-rich meals, or ask your coach for easy swaps." }
    end
  end

  def skipped_note
    if skipped_meals.zero?
      { tone: :good, title: "No skipped meals", body: "You've stuck to your planned meals so far this week." }
    else
      { tone: :high, title: "#{skipped_meals} #{'meal'.pluralize(skipped_meals)} skipped",
        body: "If a meal doesn't fit your day, your coach can adjust the plan." }
    end
  end

  def logging_note
    if unlogged_past_meals.zero?
      { tone: :good, title: "All past meals logged", body: "Your numbers are based on complete data." }
    else
      { tone: :low, title: "#{unlogged_past_meals} past #{'meal'.pluralize(unlogged_past_meals)} not logged",
        body: "Mark them as done or skipped on your meal plan so the totals stay accurate." }
    end
  end

  def fmt(number)
    ActiveSupport::NumberHelper.number_to_delimited(number)
  end
end
