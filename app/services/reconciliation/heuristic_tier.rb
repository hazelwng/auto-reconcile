module Reconciliation
  class HeuristicTier
    ONE_CENT_CONFIDENCE = 0.85
    WIDER_AMOUNT_CONFIDENCE = 0.70

    def initialize(reconciliation_run)
      @run = reconciliation_run
    end

    def call
      candidate_result = CandidateFinder.new(@run, tolerances: heuristic_tolerances).call
      uniqueness_result = UniquenessChecker.new(candidate_result.candidates).call

      TierResult.new(
        unique_candidates: uniqueness_result.unique_candidates,
        ambiguous_groups: uniqueness_result.ambiguous_groups,
        source_a_count: candidate_result.source_a_count,
        candidates_evaluated: candidate_result.candidates.size
      )
    end

    private

    def heuristic_tolerances
      {
        amount_cents: 1,
        amount_percent: 0.005,
        amount_percent_cap_cents: 500,
        bank_date_window_start_days: -2,
        bank_date_window_end_days: 14,
        method: "heuristic",
        confidence_resolver: method(:confidence_for)
      }
    end

    def confidence_for(amount_delta_cents)
      return ONE_CENT_CONFIDENCE if amount_delta_cents <= 1

      WIDER_AMOUNT_CONFIDENCE
    end
  end
end
