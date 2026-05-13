class ReconciliationRun < ApplicationRecord
  STATUSES = %w[queued running complete failed].freeze

  belongs_to :workspace
  belongs_to :source_a, class_name: "DataSource"
  belongs_to :source_b, class_name: "DataSource"
  belongs_to :triggered_by_user, class_name: "User"

  has_many :matches, dependent: :destroy
  has_many :reconciliation_exceptions, dependent: :destroy

  validates :date_range_start, :date_range_end, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validate :date_range_valid

  private

  def date_range_valid
    return if date_range_start.blank? || date_range_end.blank?
    errors.add(:date_range_end, "must be on or after start") if date_range_end < date_range_start
  end
end
