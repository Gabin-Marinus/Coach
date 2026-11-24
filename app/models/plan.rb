class Plan < ApplicationRecord
  belongs_to :user
  has_many :workouts, dependent: :destroy
  has_many :meals, dependent: :destroy

  GOALS = {
    "lose_fat" => "Lose weight / body fat",
    "build_muscle" => "Build muscle",
    "maintain" => "Maintain my weight",
    "get_stronger" => "Get stronger",
    "improve_endurance" => "Improve endurance / cardio fitness",
    "improve_mobility" => "Improve flexibility and mobility",
    "general_health" => "Feel healthier overall"
  }.freeze

  STATUSES = %w[active archived].freeze

  validates :goal, presence: true, inclusion: { in: GOALS.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :start_date, :end_date, presence: true
  validate :end_date_after_start_date

  scope :active, -> { where(status: "active") }

  after_create :archive_previous_plans

  def goal_label
    GOALS[goal]
  end

  private

  def end_date_after_start_date
    return if start_date.blank? || end_date.blank?

    errors.add(:end_date, "must be after the start date") if end_date < start_date
  end

  def archive_previous_plans
    user.plans.active.where.not(id: id).update_all(status: "archived")
  end
end
