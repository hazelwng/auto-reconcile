class Workspace < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :data_sources, dependent: :destroy
  has_many :import_batches, through: :data_sources
  has_many :bank_transactions, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :reconcilable_items, dependent: :destroy
  has_many :reconciliation_runs, dependent: :destroy
  has_many :matches, dependent: :destroy
  has_many :reconciliation_exceptions, dependent: :destroy
  has_many :audit_events, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }
  validates :base_currency, presence: true, length: { is: 3 }
end
