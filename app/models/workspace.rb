class Workspace < ApplicationRecord
  SUPPORTED_COUNTRY_CODES = %w[AU JP].freeze

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
  validates :country_code, presence: true, inclusion: { in: SUPPORTED_COUNTRY_CODES }

  before_validation :normalize_country_code

  private

  def normalize_country_code
    self.country_code = country_code.to_s.upcase.presence
  end
end
