module Reconciliation
  class ExactTier
    def initialize(reconciliation_run)
      @run = reconciliation_run
    end

    def call
      candidate_result = CandidateFinder.new(@run, tolerances: exact_tolerances).call
      uniqueness_result = UniquenessChecker.new(candidate_result.candidates).call

      TierResult.new(
        unique_candidates: uniqueness_result.unique_candidates,
        ambiguous_groups: uniqueness_result.ambiguous_groups,
        source_a_count: candidate_result.source_a_count,
        candidates_evaluated: candidate_result.candidates.size
      )
    end

    private

    def exact_tolerances
      {
        amount_cents: 0,
        amount_percent: 0.0,
        amount_percent_cap_cents: 0,
        bank_date_window_start_days: 0,
        bank_date_window_end_days: 7,
        method: "exact",
        confidence_resolver: ->(_amount_delta_cents) { 1.0 }
      }
    end
  end
end
