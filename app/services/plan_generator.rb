class PlanGenerator
  def initialize(chat)
    @chat = chat
    @user = chat.user
  end

  def call
    data = JSON.parse(clean_json(ask_llm))

    ActiveRecord::Base.transaction do
      plan = @user.plans.create!(data.slice("goal", "start_date", "end_date"))

      Array(data["workouts"]).each do |workout|
        plan.workouts.create!(workout.slice("date", "name", "description", "duration_min"))
      end

      Array(data["meals"]).each do |meal|
        plan.meals.create!(meal.slice("date", "meal_type", "name", "description", "recipe",
                                      "calories", "protein_g", "carbs_g", "fat_g"))
      end

      plan
    end
  end

  private

  def ask_llm
    RubyLLM.chat.with_instructions(prompt).ask(conversation).content
  end

  def conversation
    @chat.messages
         .where(role: %w[user assistant])
         .order(:created_at)
         .map { |message| "#{message.role.upcase}: #{message.content}" }
         .join("\n\n")
  end

  def clean_json(text)
    text.gsub(/```(json)?/, "").strip
  end

  def prompt
    <<~PROMPT
      You convert a coaching conversation into a structured plan.
      Use the LAST plan the assistant proposed in the conversation.
      Today is #{Date.today}. The plan starts today and lasts 7 days.

      Return ONLY valid JSON, with no text before or after, in exactly this format:
      {
        "goal": "one of: #{Plan::GOALS.keys.join(", ")}",
        "start_date": "YYYY-MM-DD",
        "end_date": "YYYY-MM-DD",
        "workouts": [
          { "date": "YYYY-MM-DD", "name": "string", "description": "string", "duration_min": 45 }
        ],
        "meals": [
          { "date": "YYYY-MM-DD", "meal_type": "one of: #{Meal::MEAL_TYPES.keys.join(", ")}",
            "name": "string", "description": "string", "recipe": "string",
            "calories": 500, "protein_g": 30, "carbs_g": 50, "fat_g": 15 }
        ]
      }
    PROMPT
  end
end
