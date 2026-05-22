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

  CANONICAL_DATA_SOURCE_NAMES = {
    "bank"       => "Bank",
    "accounting" => "Invoices"
  }.freeze

  PeriodOptions = Struct.new(:options, :default_id, :min, :max, keyword_init: true) do
    # Returns [start_date, end_date] for the given option id, or nil if the
    # id is unknown. The "all" id returns the full min..max window; month
    # ids ("2025-10") return that month's bounds.
    def find_range(id)
      return [ min, max ] if id == "all" && min && max
      opt = options.find { |o| o[:id] == id.to_s }
      return nil unless opt
      [ opt[:start], opt[:finish] ]
    end
  end

  # Returns the workspace's canonical data source for the given kind,
  # creating it (with a canonical name and the workspace's base currency)
  # if none exists. The landing/upload flow uses this to avoid forcing the
  # user to think about data sources at all.
  def default_data_source(kind)
    kind = kind.to_s
    unless CANONICAL_DATA_SOURCE_NAMES.key?(kind)
      raise ArgumentError, "default_data_source supports bank/accounting only, got #{kind.inspect}"
    end

    data_sources.kept.where(kind: kind).order(:id).first ||
      data_sources.create!(
        name: CANONICAL_DATA_SOURCE_NAMES.fetch(kind),
        kind: kind,
        currency: base_currency,
        schema_mapping: {}
      )
  end

  # Builds the Period dropdown options shown on the landing page from the
  # workspace's imported items. Each distinct month with data becomes an
  # option (newest first), plus an "All uploaded data" option when the data
  # spans more than one month. The default selection is the most recent
  # month — so the demo path with single-month sample data is zero-decision,
  # and real users defaulting to "the month they're closing" still works.
  def period_options
    dates = reconcilable_items.kept.pluck(:occurred_on).compact.uniq
    return PeriodOptions.new(options: [], default_id: nil, min: nil, max: nil) if dates.empty?

    min_date = dates.min
    max_date = dates.max
    months = dates.map { |d| Date.new(d.year, d.month, 1) }.uniq.sort.reverse

    options = months.map do |m|
      {
        id:     m.strftime("%Y-%m"),
        label:  m.strftime("%b %Y"),
        start:  m,
        finish: m.end_of_month
      }
    end

    if months.size > 1
      options << {
        id:     "all",
        label:  "All uploaded data",
        start:  min_date,
        finish: max_date
      }
    end

    PeriodOptions.new(
      options: options,
      default_id: months.first.strftime("%Y-%m"),
      min: min_date,
      max: max_date
    )
  end
end
