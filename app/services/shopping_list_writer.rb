# Writes the weekly shopping lists of a plan and saves them in plan.shopping_lists.
#
# The meals repeat every 2 weeks, so there are 2 lists. Ruby adds up the ingredients of the week's meals
# ("rolled oats: 420 g"), then the AI turns those totals into a short list you can really shop with:
# similar items merged, shop packs ("1 bag (500 g)", "10"), tips ("frozen is fine") and pantry staples apart.
class ShoppingListWriter
  # Tips are added by keyword (the AI put tips on almost everything): first match wins
  TIPS = {
    /frozen|canned/ => nil,
    /berr/ => "frozen is fine",
    /mixed vegetable|stir.?fry|vegetable mix|\bpeas|green beans/ => "frozen is fine", # \b: not chickpeas
    /chickpea|bean|lentil/ => "canned is fine",
    /spinach|kale|salad|greens|lettuce|rocket/ => "buy pre-washed",
    /pumpkin|squash/ => "buy pre-cut",
    /avocado|banana/ => "pick ripe ones"
  }.freeze

  PROMPT = <<~PROMPT
    You turn the ingredient totals of one week of meals into a short, practical supermarket
    shopping list for one person. It must be easy to use in the shop and not overwhelming.

    Rules:
    - Every ingredient in the totals must end up in "items" or in "pantry". Never leave one out.
    - Only merge ingredients that are the same product: "spinach" and "baby spinach" => "Spinach";
      "tomato" and "tomatoes" => "Tomatoes"; "stock" and "vegetable stock" => "Vegetable stock".
      Different vegetables stay separate items.
    - "buy" is what to put in the basket, in shop units, rounded up, as sold in the user's country:
      "10" for pieces (bananas, apples, onions), "1 bag (500 g)", "2 cans (400 g)", "1 box of 10",
      "1 carton (1 l)", "1 head", "1 bunch". Never a gram amount on its own for something sold in packs.
    - "pantry": the staples from the totals that most kitchens already have (oil, salt, pepper, spices,
      dried herbs, vinegar, soy sauce, honey, mustard, stock cubes, flour, sugar). Only ingredients
      that are in the totals, lowercase names. These are not repeated in "items".
    - Short, everyday names, capitalized (e.g. "Rolled oats", "Frozen mixed berries").
    - category: the supermarket aisle. Lentils, beans, chickpeas, nuts and seeds are "Cans & jars"
      (dry or canned), not "Dairy & eggs". Tofu goes with "Dairy & eggs" (chilled section).
    - "buy" is short (at most 4 words), no explanations.
  PROMPT

  # Structured output: OpenAI must answer with JSON in exactly this shape, so it can't be broken
  SCHEMA = {
    name: "shopping_list",
    strict: true,
    schema: {
      type: "object",
      additionalProperties: false,
      required: %w[items pantry],
      properties: {
        items: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[name buy category],
            properties: {
              name: { type: "string" },
              buy: { type: "string" },
              category: { type: "string", enum: Meal::SHOPPING_CATEGORIES }
            }
          }
        },
        pantry: { type: "array", items: { type: "string" } }
      }
    }
  }.freeze

  def initialize(plan)
    @plan = plan
  end

  def call
    weeks = (1..PlanGenerator::WEEKS_IN_ROTATION).to_h { |week| [week.to_s, week_meals(week)] }.compact
    questions = weeks.transform_values { |meals| question(meals) }

    # Both weeks at the same time, so saving a plan isn't twice as slow.
    # Only the AI calls run in threads: the database is used before and after.
    answers = questions.to_h { |week, question| [week, Thread.new { ask(question) }] }
                       .transform_values(&:value)
                       .compact # a week that failed is left out: the "Create shopping list" button can retry

    lists = answers.to_h { |week, answer| [week, clean(answer, weeks[week])] }
    @plan.update!(shopping_lists: @plan.shopping_lists.merge(lists))
  end

  private

  # nil when the week's meals have no ingredients yet (see MealIngredients)
  def week_meals(week)
    meals = @plan.meals.where(date: @plan.week_dates(week)).to_a
    meals unless meals.empty? || meals.any? { |meal| meal.ingredients.empty? }
  end

  def question(meals)
    country = @plan.user.country.presence || "not informed"
    "Country: #{country}\n\nIngredient totals for the week:\n#{totals(meals).join("\n")}"
  end

  # "- rolled oats: 420 g (Bread & grains)"; "tomato" and "tomatoes" are added together
  def totals(meals)
    grouped = meals.flat_map(&:ingredients).group_by { |ingredient|
 [ingredient["name"].singularize, ingredient["unit"]] }
    grouped.map do |(_, unit), ingredients|
      quantity = ingredients.filter_map { |ingredient| ingredient["quantity"] }.sum
      amount = quantity.positive? ? "#{quantity.round} #{unit}".strip : "to taste"
      "- #{ingredients.first['name']}: #{amount} (#{ingredients.first['category']})"
    end
  end

  # nil if the AI is unavailable, so one failed week doesn't lose the other
  def ask(question)
    RubyLLM.chat.with_instructions(PROMPT).with_thinking(effort: :low).with_schema(SCHEMA).ask(question).parsed
  rescue RubyLLM::Error, JSON::ParserError => e
    Rails.logger.warn("[ShoppingListWriter] #{e.class}: #{e.message}")
    nil
  end

  def clean(answer, meals)
    # The AI sometimes lists every pantry staple it knows: keep only the ones the meals really use
    used = meals.flat_map(&:ingredients).map { |ingredient| ingredient["name"] }.uniq
    pantry = Array(answer["pantry"]).map { |name| name.to_s.strip.downcase }.compact_blank.uniq
                                    .select { |name| used.any? { |ingredient|
 ingredient.include?(name) || name.include?(ingredient) } }

    items = Array(answer["items"]).filter_map do |item|
      next unless item.is_a?(Hash) && item["name"].present?

      {
        "name" => item["name"].to_s.strip.first(40),
        "buy" => item["buy"].to_s.strip.first(40),
        "category" => (Meal::SHOPPING_CATEGORIES.include?(item["category"]) ? item["category"] : "Other"),
        "tip" => tip_for(item["name"].to_s.downcase)
      }
    end
    items.reject! { |item| item["name"].downcase.in?(pantry) } # not twice
    { "items" => items, "pantry" => pantry }
  end

  def tip_for(name)
    TIPS.find { |pattern, _| name.match?(pattern) }&.last
  end
end
