# Asks the AI which fruits and vegetables are in season where the user lives,
# and saves the list on the user. Only asks again when the month or location changes.
class SeasonalProduce
  PROMPT = <<~PROMPT
    You are a nutrition expert who knows food markets around the world.
    List the fruits and vegetables that are in season and easy to find in local shops and markets
    in the given location during the given month. Mind the hemisphere and the local climate.
    Prefer produce grown locally or in the region. Use common English names.
    Give 6 to 10 fruits and 8 to 12 vegetables.
    Return ONLY valid JSON, with no text before or after, in exactly this format:
    { "fruits": ["string"], "vegetables": ["string"] }
  PROMPT

  def initialize(user, date: Date.today)
    @user = user
    @date = date
  end

  # Returns { "fruits" => [...], "vegetables" => [...] }, or {} if we can't know it
  def call
    return {} if @user.location.blank?
    return @user.seasonal_produce if up_to_date?

    produce = ask_ai
    @user.update_columns(seasonal_produce: produce, seasonal_produce_key: key)
    produce
  rescue RubyLLM::Error, JSON::ParserError => e
    Rails.logger.warn("[SeasonalProduce] #{e.class}: #{e.message}")
    {}
  end

  private

  def up_to_date?
    @user.seasonal_produce_key == key && @user.seasonal_produce.present?
  end

  def key
    "#{@date.strftime('%Y-%m')} #{@user.location.downcase}"
  end

  def ask_ai
    question = "Location: #{@user.location}\nMonth: #{@date.strftime('%B')}"
    text = RubyLLM.chat.with_instructions(PROMPT).ask(question).content
    data = JSON.parse(text.gsub(/```(json)?/, "").strip)

    {
      "fruits" => Array(data["fruits"]).map(&:to_s).first(10),
      "vegetables" => Array(data["vegetables"]).map(&:to_s).first(12)
    }
  end
end
