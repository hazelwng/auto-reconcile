class ReconcilableItem < ApplicationRecord
  include Discard::Model

  STATUSES = %w[unmatched proposed matched exception ignored].freeze

  delegated_type :item, types: %w[BankTransaction Invoice], dependent: :destroy

  belongs_to :workspace
  belongs_to :data_source
  belongs_to :import_batch

  has_many :match_legs, dependent: :restrict_with_exception
  has_many :matches, through: :match_legs
  has_many :reconciliation_exceptions, dependent: :restrict_with_exception

  monetize :amount_cents, with_model_currency: :amount_currency

  validates :amount_cents, presence: true
  validates :amount_currency, presence: true, length: { is: 3 }
  validates :occurred_on, presence: true
  validates :external_id_hash, presence: true,
            uniqueness: { scope: :data_source_id }
  validates :status, presence: true, inclusion: { in: STATUSES }
end
