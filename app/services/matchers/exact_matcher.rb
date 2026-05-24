module Matchers
  # Builds exact 1:1 matches between source_a (accounting/AR invoices) and
  # source_b (bank transactions) for a given ReconciliationRun.
  #
  # Candidate filter (A is invoice, B is bank):
  #   - both items belong to run.workspace
  #   - a.data_source_id == run.source_a_id
  #   - b.data_source_id == run.source_b_id
  #   - both items are "unmatched"
  #   - a.amount_cents == b.amount_cents (sign already normalized at import)
  #   - a.amount_currency == b.amount_currency
  #   - a.occurred_on in run.date_range_start..run.date_range_end
  #   - b.occurred_on >= a.occurred_on and b.occurred_on <= a.occurred_on + 7 days
  #
  # Uniqueness rule (bidirectional): a candidate edge (A, B) becomes a match
  # only if its connected component in the bipartite candidate graph is
  # exactly one A and one B. Any other component shape is an ambiguity
  # group; every involved item becomes an exception with category "duplicate"
  # and metadata { group_key, subcategory: "ambiguity", reason,
  # involved_item_ids, source_a_item_ids, source_b_item_ids }.
  #
  # Concurrency: each component is processed in its own transaction, with
  # the involved items locked via SELECT FOR UPDATE in ascending id order
  # (deadlock-safe). Status is re-checked under the lock; if any item has
  # been touched by another worker, the component is skipped.
  class ExactMatcher
    BANK_DATE_WINDOW_DAYS = 7

    def initialize(reconciliation_run)
      @run = reconciliation_run
    end

    def call
      validate_run!
      stats = empty_stats

      candidate_result = Reconciliation::CandidateFinder.new(@run).call
      stats[:source_a_in_window] = candidate_result.source_a_count
      return stats if candidate_result.source_a_count.zero?

      stats[:candidates_evaluated] = candidate_result.candidates.size

      uniqueness_result = Reconciliation::UniquenessChecker.new(candidate_result.candidates).call
      committer = Reconciliation::MatchCommitter.new(@run)

      uniqueness_result.unique_candidates.each do |candidate|
        merge_result!(stats, committer.commit_exact_candidate(candidate))
      end

      uniqueness_result.ambiguous_groups.each do |group|
        merge_result!(stats, committer.commit_ambiguity(group))
      end

      stats[:source_a_unmatched] = stats[:source_a_in_window] -
                                   stats[:source_a_matched] -
                                   stats[:source_a_exceptions]
      stats
    end

    private

    # Fail fast on misconfigured runs. These are programmer/operator errors,
    # not data errors, so we raise rather than silently producing nonsense.
    def validate_run!
      if @run.source_a_id == @run.source_b_id
        raise ArgumentError, "source_a and source_b must differ (both are data_source ##{@run.source_a_id})"
      end
      unless @run.source_a.workspace_id == @run.workspace_id
        raise ArgumentError, "source_a belongs to workspace ##{@run.source_a.workspace_id}, run is in workspace ##{@run.workspace_id}"
      end
      unless @run.source_b.workspace_id == @run.workspace_id
        raise ArgumentError, "source_b belongs to workspace ##{@run.source_b.workspace_id}, run is in workspace ##{@run.workspace_id}"
      end
      unless @run.source_a.kind == "accounting"
        raise ArgumentError, "source_a.kind must be 'accounting' (got #{@run.source_a.kind.inspect})"
      end
      unless @run.source_b.kind == "bank"
        raise ArgumentError, "source_b.kind must be 'bank' (got #{@run.source_b.kind.inspect})"
      end
    end

    def empty_stats
      {
        candidates_evaluated: 0,
        matches_created: 0,
        exceptions_created: 0,
        ambiguity_groups_created: 0,
        source_a_in_window: 0,
        source_a_matched: 0,
        source_a_exceptions: 0,
        source_a_unmatched: 0
      }
    end

    def merge_result!(stats, result)
      case result[:kind]
      when :matched
        stats[:matches_created] += 1
        stats[:source_a_matched] += 1
      when :ambiguous
        stats[:ambiguity_groups_created] += 1
        stats[:exceptions_created] += result[:items_count]
        stats[:source_a_exceptions] += result[:source_a_count]
      end
    end
  end
end
