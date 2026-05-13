class BankTransaction < ApplicationRecord
  include ReconcilableItem::Item
  include Discard::Model

  TXN_TYPES = %w[debit credit].freeze

  belongs_to :workspace

  monetize :balance_after_cents,
           with_model_currency: :balance_after_currency,
           allow_nil: true

  validates :posted_date, presence: true
  validates :txn_type, presence: true, inclusion: { in: TXN_TYPES }
end
