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

    lists = self.class.ingredients_for(unique_meals.map { |meal| meal.slice(:name, :description, :recipe).stringify_keys })
    unique_meals.zip(lists).each do |meal, ingredients|
      next if ingredients.blank?

      @plan.meals.without_ingredients.where(name: meal.name).update_all(ingredients: ingredients)
    end
  end

  # [{ "name", "description", "recipe" }] => their ingredients, in the same order (nil if the AI skipped one).
  # AI only (no database), so PlanGenerator can also use it to complete meals with missing ingredients.
  def self.ingredients_for(meals)
    question = meals.each_with_index.map do |meal, index|
      "#{index + 1}. #{meal['name']}: #{meal['description']} Recipe: #{meal['recipe']}"
    end.join("\n")

    # "low": listing ingredients needs little thinking, so the answer is much faster ("minimal" forgets the quantities)
    answer = RubyLLM.chat.with_instructions(PROMPT).with_thinking(effort: :low).with_schema(SCHEMA).ask(question).parsed
    by_number = Array(answer["meals"]).to_h { |result| [result["number"].to_i, Meal.clean_ingredients(result["ingredients"])] }
    meals.each_index.map { |index| by_number[index + 1] }
  end
end
