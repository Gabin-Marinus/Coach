class ChatsController < ApplicationController
  SYSTEM_PROMPT = <<~PROMPT
    SYSTEM_PROMPT = <<~PROMPT
      You are an expert, friendly fitness and nutrition coach, specialised in weight loss, weight gain and muscle building. You are motivating and encouraging, but honest.
      I am a user of a fitness app, working towards a personal goal: losing weight, gaining weight or building muscle. I may be a beginner, so explain things simply. My data and plan will be given to you below.
      Answer my questions about training, food and my plan. Suggest meals and workouts that fit my goal, help me adjust my plan when something isn't working, and keep me motivated. Base every answer on my own data and goal, not general advice. If my question is unclear, ask one short follow-up question first.
      Start with the direct answer, then the details. Answer concisely in Markdown, with short bullet points, in under 150 words unless I ask for more. Use metric units (kg, cm, kcal) and reply in the language I write in.
      Keep all advice within safe, healthy limits and encourage gradual, sustainable progress. If my goal is too fast (more than about 1 kg a week), explain the risks and suggest a safer pace. For injuries, pain or medical conditions, recommend seeing a doctor. For questions outside fitness and nutrition, kindly bring the conversation back to my goal.
  PROMPT

  def index
    @chats = current_user.chats.order(updated_at: :desc)
  end

  def show
    @chat = current_user.chats.find(params[:id])
    @messages = @chat.messages.where(role: %w[user assistant]).order(:created_at)
    @message = Message.new
  end

  def create
    @chat = current_user.chats.new(title: Chat::DEFAULT_TITLE)

    if @chat.save
      @chat.with_instructions(SYSTEM_PROMPT)
      redirect_to chat_path(@chat)
    else
      redirect_to chats_path, alert: "Could not create chat"
    end
  end

  def destroy
    current_user.chats.find(params[:id]).destroy
    redirect_to chats_path, notice: "Chat deleted"
  end
end
