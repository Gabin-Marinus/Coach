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
    Ingredients (used for the weekly shopping list, so it must be COMPLETE):
    - EVERY ingredient needed to cook the recipe, for ONE serving: nothing may be missing.
      Every ingredient named in the recipe is in the list, and every listed ingredient is used in the recipe.
    - Sauces and bases are split into their ingredients: béchamel = milk, butter, flour;
      curry = onion, garlic, curry paste, canned tomatoes, coconut milk; a dressing = oil, lemon, mustard.
    - Include the liquid (milk for overnight oats or porridge, stock for soup), the aromatics (onion, garlic,
      ginger), the vegetables of the dish, the pasta or lasagna sheets, cheese, oil and spices.
      Only water is never listed.
    - A leftovers meal lists the full ingredients of its serving again (the dish was cooked for 2 servings).
    - Simple supermarket names, always the same name for the same
      ingredient (e.g. "rolled oats", "frozen mixed berries", "canned chickpeas", "spinach", "milk").
      The name is only the product: no notes, uses or choices ("milk", not "milk (for béchamel)";
      "curry powder", not "curry powder or spices"; "brown rice", not "brown rice (dry)").
    - unit is one of: #{INGREDIENT_UNITS.join(', ')} (pcs = pieces, e.g. eggs, bananas, onions, garlic cloves).
      Pasta, lasagna sheets, rice, oats, bread, meat, fish, cheese and vegetables you weigh are in g
      (dry weight for pasta and rice, e.g. 90 g lasagna sheets, 75 g rice), liquids in ml.
    - category is one of: #{SHOPPING_CATEGORIES.join(', ')}.
    - "quantity" is ALWAYS a number with its unit (e.g. 60 g oats, 150 ml milk, 1 pcs onion, 5 ml oil),
      except salt, pepper and spices "to taste": null.
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
