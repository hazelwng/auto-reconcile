module ReconcilableItem::Item
  extend ActiveSupport::Concern

  included do
    has_one :reconcilable_item, as: :item, touch: true, inverse_of: :item
  end
end
