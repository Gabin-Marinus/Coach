class Meal < ApplicationRecord
  belongs_to :plan

  MEAL_TYPES = {
    "breakfast" => "Breakfast",
    "lunch" => "Lunch",
    "dinner" => "Dinner",
    "snack" => "Snack"
  }.freeze

  STATUSES = %w[planned done skipped].freeze

  validates :date, :name, presence: true
  validates :meal_type, inclusion: { in: MEAL_TYPES.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :calories, :protein_g, :carbs_g, :fat_g,
            numericality: { greater_than_or_equal_to: 0 }, allow_blank: true

  scope :for_date, ->(date) { where(date: date) }

  # Breakfast, lunch, dinner, snack
  def self.in_day_order(meals)
    meals.sort_by { |meal| MEAL_TYPES.keys.index(meal.meal_type) || MEAL_TYPES.size }
  end

  def done?
    status == "done"
  end
end
