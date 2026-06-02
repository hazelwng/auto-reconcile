require "test_helper"

module Reconciliation
  class UniquenessCheckerTest < ActiveSupport::TestCase
    test "classifies isolated one-to-one candidate as unique" do
      result = UniquenessChecker.new([
        candidate(1, 10)
      ]).call

      assert_equal 1, result.unique_candidates.size
      assert_empty result.ambiguous_groups
      assert_equal 1, result.unique_candidates.first.source_a_item_id
      assert_equal 10, result.unique_candidates.first.source_b_item_id
    end

    test "groups one-to-many candidates as ambiguity" do
      result = UniquenessChecker.new([
        candidate(1, 10),
        candidate(1, 11)
      ]).call

      assert_empty result.unique_candidates
      group = result.ambiguous_groups.sole
      assert_equal [ 1 ], group.source_a_item_ids
      assert_equal [ 10, 11 ], group.source_b_item_ids
      assert_equal "1 invoice with 2 bank candidates", group.reason
    end

    test "groups connected many-to-many candidates as one ambiguity" do
      result = UniquenessChecker.new([
        candidate(1, 10),
        candidate(1, 11),
        candidate(2, 11)
      ]).call

      assert_empty result.unique_candidates
      group = result.ambiguous_groups.sole
      assert_equal [ 1, 2 ], group.source_a_item_ids
      assert_equal [ 10, 11 ], group.source_b_item_ids
      assert_equal "2 invoices with 2 bank candidates (overlapping)", group.reason
    end

    test "ambiguity metadata serializes ids and reason for exception records" do
      group = AmbiguityGroup.new(source_a_item_ids: [ 2, 1 ], source_b_item_ids: [ 11, 10 ])

      assert_equal({
        "group_key" => "group-1",
        "subcategory" => "ambiguity",
        "reason" => "2 invoices with 2 bank candidates (overlapping)",
        "involved_item_ids" => [ 1, 2, 10, 11 ],
        "source_a_item_ids" => [ 1, 2 ],
        "source_b_item_ids" => [ 10, 11 ]
      }, group.metadata(group_key: "group-1"))
    end

    private

    def candidate(source_a_item_id, source_b_item_id)
      Candidate.new(
        source_a_item_id: source_a_item_id,
        source_b_item_id: source_b_item_id,
        matched_on: {}
      )
    end
  end
end
