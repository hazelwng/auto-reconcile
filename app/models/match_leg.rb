class MatchLeg < ApplicationRecord
  SIDES = %w[a b].freeze

  belongs_to :match
  belongs_to :reconcilable_item

  monetize :allocated_amount_cents, with_model_currency: :allocated_currency

  validates :side, presence: true, inclusion: { in: SIDES }
  validates :allocated_amount_cents, presence: true
  validates :allocated_currency, presence: true, length: { is: 3 }
  validates :reconcilable_item_id, uniqueness: { scope: :match_id }
  validate :confirmed_allocations_do_not_exceed_item_amount

  private

  def confirmed_allocations_do_not_exceed_item_amount
    return unless match&.status == "confirmed" && reconcilable_item.present?

    confirmed_allocated_cents = reconcilable_item.match_legs
      .joins(:match)
      .where(matches: { status: "confirmed" })
      .where.not(match_legs: { id: id })
      .sum(:allocated_amount_cents)

    max_allocatable_cents = reconcilable_item.amount_cents.abs
    requested_cents = confirmed_allocated_cents + allocated_amount_cents.to_i

    return if requested_cents <= max_allocatable_cents

    errors.add(:allocated_amount_cents, "exceeds the item's remaining amount")
  end
end
