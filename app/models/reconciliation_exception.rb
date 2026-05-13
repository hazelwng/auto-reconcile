class ReconciliationException < ApplicationRecord
  CATEGORIES = %w[timing missing duplicate amount_mismatch currency_mismatch unknown].freeze
  RESOLUTIONS = %w[matched_manually ignored written_off].freeze

  belongs_to :reconciliation_run
  belongs_to :reconcilable_item
  belongs_to :workspace
  belongs_to :resolved_by_user, class_name: "User", optional: true

  validates :category, presence: true, inclusion: { in: CATEGORIES }
  validates :resolution, inclusion: { in: RESOLUTIONS }, allow_nil: true
  validates :reconcilable_item_id, uniqueness: { scope: :reconciliation_run_id }
end
