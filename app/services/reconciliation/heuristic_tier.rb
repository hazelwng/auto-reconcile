module Reconciliation
  class HeuristicTier
    def initialize(reconciliation_run, policy:)
      @run = reconciliation_run
      @policy = policy
    end

    def call
      candidate_result = CandidateFinder.new(@run, tolerances: @policy.heuristic_tolerances).call
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
