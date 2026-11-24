class Plan < ApplicationRecord
  belongs_to :user
  has_many :workouts, dependent: :destroy
  has_many :meals, dependent: :destroy

  STATUSES = %w[active archived].freeze


  # Take the user's current goals if none were given
  before_validation { self.goals = user.goals if goals.blank? && user }

  validates :goals, presence: true
  validate :goals_are_valid
  validates :status, inclusion: { in: STATUSES }
  validates :start_date, :end_date, presence: true
  validate :end_date_after_start_date

  scope :active, -> { where(status: "active") }

  after_create :archive_previous_plans

  def goal_labels
    goals.map { |g| User::GOALS[g] }
  end

  private

  def goals_are_valid
    invalid = goals - User::GOALS.keys
    errors.add(:goals, "has invalid options: #{invalid.join(', ')}") if invalid.any?
  end

  def end_date_after_start_date
    return if start_date.blank? || end_date.blank?

    errors.add(:end_date, "must be after the start date") if end_date < start_date
  end

  def archive_previous_plans
    user.plans.active.where.not(id: id).update_all(status: "archived")
  end
end
