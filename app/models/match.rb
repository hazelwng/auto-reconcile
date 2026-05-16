class Match < ApplicationRecord
  include Discard::Model

  METHODS = %w[exact rule embedding llm manual].freeze
  STATUSES = %w[proposed confirmed rejected].freeze

  belongs_to :reconciliation_run
  belongs_to :workspace
  belongs_to :confirmed_by_user, class_name: "User", optional: true

  has_many :match_legs, dependent: :destroy
  has_many :reconcilable_items, through: :match_legs

  validates :method, presence: true, inclusion: { in: METHODS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :confidence, presence: true,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
end
