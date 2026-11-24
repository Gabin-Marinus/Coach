class Workout < ApplicationRecord
  belongs_to :plan

  STATUSES = %w[planned done skipped].freeze

  validates :date, :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :duration_min, numericality: { greater_than: 0 }, allow_blank: true

  scope :for_date, ->(date) { where(date: date) }
end
