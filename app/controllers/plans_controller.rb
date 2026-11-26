class PlansController < ApplicationController
  def create
    @chat = current_user.chats.plan_chats.find(params[:chat_id])

    unless current_user.ready_for_plan?
      redirect_to edit_profile_path, alert: "Please complete your profile and goals before saving a plan."
      return
    end

    PlanGenerator.new(@chat).call
    redirect_to workouts_profile_path, notice: "Your 1-month plan was saved! 🎉"
  rescue JSON::ParserError, ActiveRecord::RecordInvalid, RubyLLM::Error, PlanGenerator::Error
    redirect_to chat_path(@chat), alert: "Sorry, we couldn't save your plan. Please try again."
  end

  # "Explain this plan" button, for plans saved before summaries existed
  def summary
    plan = current_user.plans.find(params[:id])
    PlanSummary.new(plan).call
    redirect_back fallback_location: plan_profile_path, notice: "Here's what your plan is based on."
  rescue RubyLLM::Error
    redirect_back fallback_location: plan_profile_path, alert: "Your coach is unavailable right now. Please try again."
  end

  # "Create shopping list" button, for plans saved before shopping lists existed
  def shopping_list
    plan = current_user.plans.find(params[:id])
    first_weeks = plan.start_date...(plan.start_date + PlanGenerator::WEEKS_IN_ROTATION.weeks) # the meals repeat after that
    MealIngredients.new(plan, plan.meals.where(date: first_weeks)).call
    ShoppingListWriter.new(plan).call
    redirect_back fallback_location: plan_profile_path, notice: "Your shopping list is ready! 🛒"
  rescue RubyLLM::Error, JSON::ParserError
    redirect_back fallback_location: plan_profile_path,
                  alert: "Sorry, we couldn't make your shopping list. Please try again."
  end

  # "Add to calendar": downloads the plan as an .ics file (Google Calendar, Apple Calendar, Outlook...)
  def calendar
    @plan = current_user.plans.find(params[:id])
    @workouts = @plan.workouts.order(:date)
    @meals_by_date = @plan.meals.order(:date).group_by(&:date)

    # "attachment" makes the browser download the file instead of showing it
    response.headers["Content-Disposition"] = "attachment; filename=\"coach-plan-#{@plan.number}.ics\""
  end

  # "Delete this plan" on the My plan page
  def destroy
    plan = current_user.plans.find(params[:id])
    title = plan.title # saved before deleting, because the title counts the plans
    plan.destroy # also deletes its workouts and meals (dependent: :destroy)
    redirect_to plans_profile_path, notice: "#{title} deleted.", status: :see_other
  end

  # "Delete plans" on the All plans page
  def destroy_many
    plans = current_user.plans.where(id: params[:plan_ids])
    plans.destroy_all # also deletes their workouts and meals (dependent: :destroy)
    redirect_to plans_profile_path, notice: "Plans deleted.", status: :see_other
  end
end
