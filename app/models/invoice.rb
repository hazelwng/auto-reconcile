class Invoice < ApplicationRecord
  include ReconcilableItem::Item
  include Discard::Model

  STATUSES = %w[draft open partial paid void].freeze

  belongs_to :workspace

  monetize :total_cents, with_model_currency: :currency

  validates :invoice_number, presence: true,
            uniqueness: { scope: :workspace_id }
  validates :issue_date, presence: true
  validates :total_cents, presence: true
  validates :currency, presence: true, length: { is: 3 }
  validates :status, presence: true, inclusion: { in: STATUSES }
end
