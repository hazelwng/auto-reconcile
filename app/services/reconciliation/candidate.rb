module Reconciliation
  Candidate = Data.define(:source_a_item_id, :source_b_item_id, :matched_on) do
    def item_ids
      [ source_a_item_id, source_b_item_id ]
    end
  end
end
