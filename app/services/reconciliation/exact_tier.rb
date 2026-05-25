module Reconciliation
  class ExactTier
    def initialize(reconciliation_run)
      @run = reconciliation_run
    end

    def call
      candidate_result = CandidateFinder.new(@run).call
      uniqueness_result = UniquenessChecker.new(candidate_result.candidates).call

      TierResult.new(
        unique_candidates: uniqueness_result.unique_candidates,
        ambiguous_groups: uniqueness_result.ambiguous_groups,
        source_a_count: candidate_result.source_a_count,
        candidates_evaluated: candidate_result.candidates.size
      )
    end
  end
end
