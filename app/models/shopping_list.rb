# The shopping list of one week of a plan, as written by ShoppingListWriter.
# The meals repeat every 2 weeks, so week 3 uses the list of week 1, week 4 the list of week 2...
class ShoppingList
  Item = Struct.new(:name, :buy, :category, :tip)

  attr_reader :week

  def initialize(plan, week)
    @plan = plan
    @week = week
    @data = plan.shopping_lists[list_number.to_s]
  end

  def dates
    @plan.week_dates(@week)
  end

  # No meals planned this week
  def empty?
    !@plan.meals.where(date: dates).exists?
  end

  # False for plans saved before shopping lists existed: they get a "Create shopping list" button
  def ready?
    @data.present?
  end

  # The last week of a plan can be shorter: then you need less than the list says
  def short_week?
    dates.count < 7
  end

  def items
    Array(@data&.dig("items")).map { |item| Item.new(*item.values_at("name", "buy", "category", "tip")) }
  end

  # Oil, salt, spices...: shown as "check you have them"
  def pantry
    Array(@data&.dig("pantry"))
  end

  # { "Fruit & vegetables" => [items...], "Meat & fish" => [...] } in the shop's usual order
  def by_category
    items.group_by(&:category)
         .sort_by { |category, _| Meal::SHOPPING_CATEGORIES.index(category) || 99 }
         .to_h
  end

  private

  # 1 or 2
  def list_number
    ((@week - 1) % PlanGenerator::WEEKS_IN_ROTATION) + 1
  end
end
