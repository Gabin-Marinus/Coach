class Meal < ApplicationRecord
  belongs_to :plan

  MEAL_TYPES = {
    "breakfast" => "Breakfast",
    "lunch" => "Lunch",
    "dinner" => "Dinner",
    "snack" => "Snack"
  }.freeze

  STATUSES = %w[planned done skipped].freeze

  # Ingredients and shopping list (see ShoppingList)
  INGREDIENT_UNITS = %w[g ml pcs].freeze
  SHOPPING_CATEGORIES = [
    "Fruit & vegetables",
    "Meat & fish",
    "Dairy & eggs",
    "Bread & grains",
    "Cans & jars",
    "Frozen",
    "Other"
  ].freeze

  # How the AI must write ingredients, used by PlanGenerator and MealIngredients
  INGREDIENT_RULES = <<~RULES.freeze
    Ingredients (used for the weekly shopping list):
    - Everything for ONE serving. Simple supermarket names, always the same name for the same
      ingredient (e.g. "rolled oats", "frozen mixed berries", "canned chickpeas", "spinach").
    - unit is one of: #{INGREDIENT_UNITS.join(', ')} (pcs = pieces, e.g. eggs, bananas, onions).
    - category is one of: #{SHOPPING_CATEGORIES.join(', ')}.
    - "quantity": null for salt, pepper and spices "to taste".
  RULES

  # JSON schema of one ingredient, for the AI's structured output (see PlanGenerator, MealIngredients)
  INGREDIENT_SCHEMA = {
    type: "object",
    additionalProperties: false,
    required: %w[name quantity unit category],
    properties: {
      name: { type: "string" },
      quantity: { type: %w[number null] },
      unit: { type: %w[string null], enum: [*INGREDIENT_UNITS, nil] },
      category: { type: "string", enum: SHOPPING_CATEGORIES }
    }
  }.freeze

  validates :date, :name, presence: true
  validates :meal_type, inclusion: { in: MEAL_TYPES.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :calories, :protein_g, :carbs_g, :fat_g,
            numericality: { greater_than_or_equal_to: 0 }, allow_blank: true

  before_validation { self.ingredients = Meal.clean_ingredients(ingredients) }

  scope :for_date, ->(date) { where(date: date) }
  scope :without_ingredients, -> { where("meals.ingredients = '[]'::jsonb") }

  # Keeps only valid ingredients from the AI's answer, in the same format every time:
  # { "name" => "rolled oats", "quantity" => 60.0, "unit" => "g", "category" => "Bread & grains" }
  def self.clean_ingredients(list)
    Array(list).filter_map do |item|
      item = item.to_h.stringify_keys
      name = item["name"].to_s.strip.downcase
      next if name.blank?

      quantity = item["quantity"].to_f
      {
        "name" => name,
        "quantity" => (quantity.positive? ? quantity.round(1) : nil), # nil for "to taste"
        "unit" => (INGREDIENT_UNITS.include?(item["unit"]) ? item["unit"] : nil),
        "category" => (SHOPPING_CATEGORIES.include?(item["category"]) ? item["category"] : "Other")
      }
    end
  end
end
