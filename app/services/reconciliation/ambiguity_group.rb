module Reconciliation
  class AmbiguityGroup
    attr_reader :source_a_item_ids, :source_b_item_ids

    def initialize(source_a_item_ids:, source_b_item_ids:)
      @source_a_item_ids = source_a_item_ids.sort
      @source_b_item_ids = source_b_item_ids.sort
    end

    def item_ids
      (source_a_item_ids + source_b_item_ids).sort
    end

    def items_count
      item_ids.size
    end

    def source_a_count
      source_a_item_ids.size
    end

    def reason
      if source_a_item_ids.one?
        "1 invoice with #{source_b_item_ids.size} bank candidates"
      elsif source_b_item_ids.one?
        "#{source_a_item_ids.size} invoices with 1 bank candidate"
      else
        "#{source_a_item_ids.size} invoices with #{source_b_item_ids.size} bank candidates (overlapping)"
      end
    end

    def metadata(group_key:)
      {
        "group_key" => group_key,
        "subcategory" => "ambiguity",
        "reason" => reason,
        "involved_item_ids" => item_ids,
        "source_a_item_ids" => source_a_item_ids,
        "source_b_item_ids" => source_b_item_ids
      }
    end
  end
end
