class Workout < ApplicationRecord
  belongs_to :plan

  STATUSES = %w[planned done skipped].freeze

  validates :date, :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :duration_min, numericality: { greater_than: 0 }, allow_blank: true

  scope :for_date, ->(date) { where(date: date) }

  # The circuit as text, for the coach chat and the calendar file:
  # "Warm-up: ...", "3 rounds of, rest 60 s after each round:", "Goblet squat: 10", ..., "Cool-down: ..."
  def exercise_lines
    return [] if exercises.empty?

    rest = ", rest #{round_rest_sec} s after each round" if round_rest_sec.to_i.positive?
    [("Warm-up: #{warm_up}" if warm_up.present?),
     "#{rounds ? "#{rounds} #{'round'.pluralize(rounds)}" : 'Exercises'} of#{rest}:",
     *exercises.map { |exercise| "#{exercise['name']}: #{exercise['reps']}" },
     ("Cool-down: #{cool_down}" if cool_down.present?)].compact
  end
end
