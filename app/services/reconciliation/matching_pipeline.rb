module Reconciliation
  class MatchingPipeline
    def initialize(reconciliation_run, tiers: nil, committer: nil)
      @run = reconciliation_run
      @policy = CountryPolicy.for(reconciliation_run.workspace.country_code) if reconciliation_run
      @tiers = tiers || default_tiers
      @committer = committer || MatchCommitter.new(reconciliation_run)
    end

    def call
      stats = empty_stats
      final_ambiguous_groups = []

      @tiers.each do |tier|
        result = tier.call
        merge_tier_stats!(stats, result)

        result.unique_candidates.each do |candidate|
          merge_commit_result!(stats, @committer.commit_candidate(candidate))
        end

        final_ambiguous_groups.concat(result.ambiguous_groups)
      end

      final_ambiguous_groups.each do |group|
        merge_commit_result!(stats, @committer.commit_ambiguity(group))
      end

      stats[:source_a_unmatched] = stats[:source_a_in_window] -
                                   stats[:source_a_matched] -
                                   stats[:source_a_exceptions]
      stats
    end

    private

    def default_tiers
      [
        ExactTier.new(@run, policy: @policy),
        HeuristicTier.new(@run, policy: @policy)
      ]
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

    def merge_tier_stats!(stats, result)
      stats[:source_a_in_window] = result.source_a_count if stats[:source_a_in_window].zero?
      stats[:candidates_evaluated] += result.candidates_evaluated
    end

    def merge_commit_result!(stats, result)
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
