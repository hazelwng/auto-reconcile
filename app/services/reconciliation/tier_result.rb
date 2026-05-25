module Reconciliation
  TierResult = Data.define(
    :unique_candidates,
    :ambiguous_groups,
    :source_a_count,
    :candidates_evaluated
  )
end
