# Adds ingredients to meals saved before ingredients existed, so older plans get a shopping list too.
# New plans get their ingredients directly from PlanGenerator.
class MealIngredients
  PROMPT = <<~PROMPT
    You list the ingredients of meals from a fitness app's meal plan.

    #{Meal::INGREDIENT_RULES}
    Answer with every meal's number and its ingredients.
  PROMPT

  SCHEMA = {
    name: "meal_ingredients",
    strict: true,
    schema: {
      type: "object",
      additionalProperties: false,
      required: %w[meals],
      properties: {
        meals: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[number ingredients],
            properties: { number: { type: "integer" }, ingredients: { type: "array", items: Meal::INGREDIENT_SCHEMA } }
          }
        }
      }
    }
  }.freeze

  def initialize(plan, meals)
    @plan = plan
    @meals = meals.to_a
  end

  def call
    # The meals repeat: same name = same meal, so each meal is asked only once
    unique_meals = @meals.select { |meal| meal.ingredients.empty? }.uniq(&:name)
    return if unique_meals.empty?

    question = unique_meals.each_with_index.map do |meal, index|
      "#{index + 1}. #{meal.name}: #{meal.description} Recipe: #{meal.recipe}"
    end.join("\n")

    # "low": listing ingredients needs little thinking, so the answer is much faster ("minimal" forgets the quantities)
    answer = RubyLLM.chat.with_instructions(PROMPT).with_thinking(effort: :low).with_schema(SCHEMA).ask(question).parsed

    Array(answer["meals"]).each do |result|
      meal = unique_meals[result["number"].to_i - 1]
      next if meal.nil? || result["number"].to_i < 1

      ingredients = Meal.clean_ingredients(result["ingredients"])
      @plan.meals.without_ingredients.where(name: meal.name).update_all(ingredients: ingredients)
    end
  end
end
