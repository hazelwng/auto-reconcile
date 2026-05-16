class DataSource < ApplicationRecord
  include Discard::Model

  KINDS = %w[bank accounting payment_processor manual_csv].freeze

  belongs_to :workspace
  has_many :import_batches, dependent: :destroy
  has_many :reconcilable_items, dependent: :destroy
  has_many :source_a_reconciliation_runs,
           class_name: "ReconciliationRun",
           foreign_key: :source_a_id,
           dependent: :restrict_with_exception,
           inverse_of: :source_a
  has_many :source_b_reconciliation_runs,
           class_name: "ReconciliationRun",
           foreign_key: :source_b_id,
           dependent: :restrict_with_exception,
           inverse_of: :source_b

  validates :name, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :currency, presence: true, length: { is: 3 }
end
