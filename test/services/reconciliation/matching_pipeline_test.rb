require "test_helper"

module Reconciliation
  class MatchingPipelineTest < ActiveSupport::TestCase
    test "commits unique candidates before final ambiguous groups and returns stats" do
      unique_candidate = Candidate.new(source_a_item_id: 1, source_b_item_id: 10, matched_on: {})
      ambiguity_group = AmbiguityGroup.new(source_a_item_ids: [ 2 ], source_b_item_ids: [ 11, 12 ])
      tier = FakeTier.new(
        unique_candidates: [ unique_candidate ],
        ambiguous_groups: [ ambiguity_group ],
        source_a_count: 2,
        candidates_evaluated: 3
      )
      committer = FakeCommitter.new

      stats = MatchingPipeline.new(nil, tiers: [ tier ], committer: committer).call

      assert_equal [ [ :match, unique_candidate ], [ :ambiguity, ambiguity_group ] ], committer.calls
      assert_equal({
        candidates_evaluated: 3,
        matches_created: 1,
        exceptions_created: 3,
        ambiguity_groups_created: 1,
        source_a_in_window: 2,
        source_a_matched: 1,
        source_a_exceptions: 1,
        source_a_unmatched: 0
      }, stats)
    end

    test "does not count skipped commits" do
      tier = FakeTier.new(
        unique_candidates: [ Candidate.new(source_a_item_id: 1, source_b_item_id: 10, matched_on: {}) ],
        ambiguous_groups: [],
        source_a_count: 1,
        candidates_evaluated: 1
      )
      committer = FakeCommitter.new(match_result: { kind: :skipped })

      stats = MatchingPipeline.new(nil, tiers: [ tier ], committer: committer).call

      assert_equal 0, stats[:matches_created]
      assert_equal 1, stats[:source_a_unmatched]
    end

    class FakeTier
      def initialize(unique_candidates:, ambiguous_groups:, source_a_count:, candidates_evaluated:)
        @result = TierResult.new(
          unique_candidates: unique_candidates,
          ambiguous_groups: ambiguous_groups,
          source_a_count: source_a_count,
          candidates_evaluated: candidates_evaluated
        )
      end

      def call
        @result
      end
    end

    class FakeCommitter
      attr_reader :calls

      def initialize(match_result: { kind: :matched })
        @match_result = match_result
        @calls = []
      end

      def commit_exact_candidate(candidate)
        @calls << [ :match, candidate ]
        @match_result
      end

      def commit_ambiguity(group)
        @calls << [ :ambiguity, group ]
        {
          kind: :ambiguous,
          items_count: group.items_count,
          source_a_count: group.source_a_count
        }
      end
    end
  end
end
