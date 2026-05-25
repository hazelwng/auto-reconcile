require "test_helper"

module Matchers
  class ExactMatcherTest < ActiveSupport::TestCase
    setup do
      @workspace = workspaces(:demo)
      @user = users(:hazel)
      @source_a = data_sources(:demo_invoices) # accounting / AR
      @source_b = data_sources(:demo_bank)
      @batch_a = import_batches(:queued_invoices)
      @batch_b = import_batches(:queued_bank)
      @run = ReconciliationRun.create!(
        workspace: @workspace,
        triggered_by_user: @user,
        source_a: @source_a,
        source_b: @source_b,
        date_range_start: Date.new(2026, 4, 1),
        date_range_end: Date.new(2026, 4, 30),
        status: "running"
      )
    end

    test "happy path: one A, one B, exact match - creates Match + 2 MatchLegs, both items proposed" do
      a = make_invoice(external: "inv-1", amount_cents: 10_000, occurred_on: Date.new(2026, 4, 1))
      b = make_bank(external: "bk-1", amount_cents: 10_000, occurred_on: Date.new(2026, 4, 3))

      stats = nil
      assert_difference -> { Match.count } => 1,
                        -> { MatchLeg.count } => 2,
                        -> { ReconciliationException.count } => 0 do
        stats = ExactMatcher.new(@run).call
      end

      assert_equal "proposed", a.reload.status
      assert_equal "proposed", b.reload.status

      match = Match.last
      assert_equal "exact", match.method
      assert_equal "proposed", match.status
      assert_in_delta 1.0, match.confidence.to_f, 1e-6
      assert_match(/Exact match: amount AUD 100\.00/, match.reasoning)

      a_leg = match.match_legs.find_by(side: "a")
      b_leg = match.match_legs.find_by(side: "b")
      assert_equal a.id, a_leg.reconcilable_item_id
      assert_equal b.id, b_leg.reconcilable_item_id
      assert_equal 10_000, a_leg.allocated_amount_cents
      assert_equal 10_000, b_leg.allocated_amount_cents

      assert_equal({
        candidates_evaluated: 1,
        matches_created: 1,
        exceptions_created: 0,
        ambiguity_groups_created: 0,
        source_a_in_window: 1,
        source_a_matched: 1,
        source_a_exceptions: 0,
        source_a_unmatched: 0
      }, stats)
    end

    test "B occurred_on equal to A occurred_on is in window (boundary check)" do
      make_invoice(external: "inv-1", amount_cents: 5_000, occurred_on: Date.new(2026, 4, 10))
      make_bank(external: "bk-1", amount_cents: 5_000, occurred_on: Date.new(2026, 4, 10))

      stats = ExactMatcher.new(@run).call
      assert_equal 1, stats[:matches_created]
    end

    test "B occurred_on exactly 7 days after A is in window (boundary check)" do
      make_invoice(external: "inv-1", amount_cents: 5_000, occurred_on: Date.new(2026, 4, 1))
      make_bank(external: "bk-1", amount_cents: 5_000, occurred_on: Date.new(2026, 4, 8))

      stats = ExactMatcher.new(@run).call
      assert_equal 1, stats[:matches_created]
    end

    test "B occurred_on 8 days after A falls through to heuristic tier" do
      a = make_invoice(external: "inv-1", amount_cents: 5_000, occurred_on: Date.new(2026, 4, 1))
      b = make_bank(external: "bk-1", amount_cents: 5_000, occurred_on: Date.new(2026, 4, 9))

      stats = ExactMatcher.new(@run).call
      assert_equal 1, stats[:matches_created]
      assert_equal 0, stats[:source_a_unmatched]
      assert_equal "proposed", a.reload.status
      assert_equal "proposed", b.reload.status
      assert_equal "heuristic", Match.last.method
    end

    test "B occurred_on before A falls through to heuristic tier" do
      a = make_invoice(external: "inv-1", amount_cents: 5_000, occurred_on: Date.new(2026, 4, 10))
      b = make_bank(external: "bk-1", amount_cents: 5_000, occurred_on: Date.new(2026, 4, 9))

      stats = ExactMatcher.new(@run).call
      assert_equal 1, stats[:matches_created]
      assert_equal 0, stats[:source_a_unmatched]
      assert_equal "proposed", a.reload.status
      assert_equal "proposed", b.reload.status
      assert_equal "heuristic", Match.last.method
    end

    test "amount differs by 1 cent falls through to heuristic tier" do
      make_invoice(external: "inv-1", amount_cents: 10_000, occurred_on: Date.new(2026, 4, 1))
      make_bank(external: "bk-1", amount_cents: 10_001, occurred_on: Date.new(2026, 4, 1))

      stats = ExactMatcher.new(@run).call
      assert_equal 1, stats[:matches_created]
      assert_equal 0, stats[:source_a_unmatched]
      assert_equal "heuristic", Match.last.method
      assert_in_delta 0.85, Match.last.confidence.to_f, 1e-6
    end

    test "amount within capped percentage uses lower heuristic confidence" do
      make_invoice(external: "inv-1", amount_cents: 100_000, occurred_on: Date.new(2026, 4, 1))
      make_bank(external: "bk-1", amount_cents: 100_400, occurred_on: Date.new(2026, 4, 1))

      stats = ExactMatcher.new(@run).call
      assert_equal 1, stats[:matches_created]
      assert_equal "heuristic", Match.last.method
      assert_in_delta 0.70, Match.last.confidence.to_f, 1e-6
    end

    test "currency mismatch is not a candidate" do
      make_invoice(external: "inv-1", amount_cents: 10_000, currency: "AUD", occurred_on: Date.new(2026, 4, 1))
      make_bank(external: "bk-1", amount_cents: 10_000, currency: "USD", occurred_on: Date.new(2026, 4, 1))

      stats = ExactMatcher.new(@run).call
      assert_equal 0, stats[:matches_created]
    end

    test "A outside the run date range is not in source_a_in_window" do
      make_invoice(external: "inv-1", amount_cents: 5_000, occurred_on: Date.new(2026, 3, 31)) # before window
      make_invoice(external: "inv-2", amount_cents: 5_000, occurred_on: Date.new(2026, 5, 1))  # after window
      a = make_invoice(external: "inv-3", amount_cents: 5_000, occurred_on: Date.new(2026, 4, 15))
      make_bank(external: "bk-1", amount_cents: 5_000, occurred_on: Date.new(2026, 4, 15))

      stats = ExactMatcher.new(@run).call
      assert_equal 1, stats[:source_a_in_window]
      assert_equal 1, stats[:matches_created]
      assert_equal a.id, Match.last.match_legs.find_by(side: "a").reconcilable_item_id
    end

    test "1xN ambiguity: A has 2 candidate Bs - 3 exceptions, all flagged exception" do
      a = make_invoice(external: "inv-1", amount_cents: 10_000, occurred_on: Date.new(2026, 4, 1))
      b1 = make_bank(external: "bk-1", amount_cents: 10_000, occurred_on: Date.new(2026, 4, 2))
      b2 = make_bank(external: "bk-2", amount_cents: 10_000, occurred_on: Date.new(2026, 4, 3))

      stats = nil
      assert_difference -> { Match.count } => 0,
                        -> { ReconciliationException.count } => 3 do
        stats = ExactMatcher.new(@run).call
      end

      [ a, b1, b2 ].each { |i| assert_equal "exception", i.reload.status }

      exceptions = ReconciliationException.where(reconciliation_run: @run)
      assert_equal [ "duplicate" ], exceptions.pluck(:category).uniq
      group_keys = exceptions.map { |e| e.metadata["group_key"] }.uniq
      assert_equal 1, group_keys.size, "all exceptions in the same group should share a group_key"

      a_exception = exceptions.find_by(reconcilable_item: a)
      assert_equal "ambiguity", a_exception.metadata["subcategory"]
      assert_equal "1 invoice with 2 bank candidates", a_exception.metadata["reason"]
      # involved_item_ids includes ALL items in the group (incl. self).
      assert_equal [ a.id, b1.id, b2.id ].sort, a_exception.metadata["involved_item_ids"].sort
      assert_equal [ a.id ], a_exception.metadata["source_a_item_ids"]
      assert_equal [ b1.id, b2.id ].sort, a_exception.metadata["source_b_item_ids"].sort

      assert_equal 1, stats[:ambiguity_groups_created]
      assert_equal 3, stats[:exceptions_created]
      assert_equal 1, stats[:source_a_exceptions]
      assert_equal 0, stats[:source_a_unmatched]
      assert_equal 1, stats[:source_a_in_window]
    end

    test "Nx1 ambiguity: 2 As share 1 B candidate - 3 exceptions" do
      a1 = make_invoice(external: "inv-1", amount_cents: 7_500, occurred_on: Date.new(2026, 4, 1))
      a2 = make_invoice(external: "inv-2", amount_cents: 7_500, occurred_on: Date.new(2026, 4, 1))
      b1 = make_bank(external: "bk-1", amount_cents: 7_500, occurred_on: Date.new(2026, 4, 2))

      stats = ExactMatcher.new(@run).call

      [ a1, a2, b1 ].each { |i| assert_equal "exception", i.reload.status }
      assert_equal 3, ReconciliationException.where(reconciliation_run: @run).count
      assert_equal 1, stats[:ambiguity_groups_created]
      assert_equal 2, stats[:source_a_exceptions]
      assert_equal 0, stats[:source_a_unmatched]
      assert_equal 2, stats[:source_a_in_window]

      a_exception = ReconciliationException.find_by(reconcilable_item: a1)
      assert_equal "2 invoices with 1 bank candidate", a_exception.metadata["reason"]
      assert_equal [ a1.id, a2.id ].sort, a_exception.metadata["source_a_item_ids"].sort
      assert_equal [ b1.id ], a_exception.metadata["source_b_item_ids"]
    end

    test "connected components: shared candidate merges groups (2A, 2B) - one group of 4" do
      # A1 matches B1, B2; A2 matches B2, B3 — B2 connects them. All five
      # WAIT that's 5 items. Let me make it (2A, 2B): A1-B1, A1-B2, A2-B2.
      a1 = make_invoice(external: "inv-1", amount_cents: 9_000, occurred_on: Date.new(2026, 4, 1))
      a2 = make_invoice(external: "inv-2", amount_cents: 9_000, occurred_on: Date.new(2026, 4, 5))
      # B1: only in window for A1 (A1 4/1 - 4/8). Use 4/2.
      b1 = make_bank(external: "bk-1", amount_cents: 9_000, occurred_on: Date.new(2026, 4, 2))
      # B2: in window for both A1 (4/1-4/8) and A2 (4/5-4/12). Use 4/6.
      b2 = make_bank(external: "bk-2", amount_cents: 9_000, occurred_on: Date.new(2026, 4, 6))

      stats = ExactMatcher.new(@run).call

      # B1 is a candidate of A1 only. B2 is a candidate of both A1 and A2.
      # So the component is {A1, A2, B1, B2}.
      [ a1, a2, b1, b2 ].each { |i| assert_equal "exception", i.reload.status }
      assert_equal 4, ReconciliationException.where(reconciliation_run: @run).count
      assert_equal 1, stats[:ambiguity_groups_created]
      assert_equal 2, stats[:source_a_exceptions]
    end

    test "A with no candidates remains unmatched and is not in any component" do
      a = make_invoice(external: "inv-1", amount_cents: 5_000, occurred_on: Date.new(2026, 4, 1))

      stats = ExactMatcher.new(@run).call
      assert_equal "unmatched", a.reload.status
      assert_equal 0, stats[:matches_created]
      assert_equal 0, stats[:exceptions_created]
      assert_equal 1, stats[:source_a_unmatched]
      assert_equal 1, stats[:source_a_in_window]
    end

    test "stats invariant: matched + exceptions + unmatched == in_window across mixed scenarios" do
      # Unique match.
      make_invoice(external: "inv-1", amount_cents: 1_000, occurred_on: Date.new(2026, 4, 1))
      make_bank(external: "bk-1", amount_cents: 1_000, occurred_on: Date.new(2026, 4, 1))
      # Ambiguity 1xN.
      make_invoice(external: "inv-2", amount_cents: 2_000, occurred_on: Date.new(2026, 4, 5))
      make_bank(external: "bk-2", amount_cents: 2_000, occurred_on: Date.new(2026, 4, 5))
      make_bank(external: "bk-3", amount_cents: 2_000, occurred_on: Date.new(2026, 4, 6))
      # Unmatched A.
      make_invoice(external: "inv-3", amount_cents: 3_000, occurred_on: Date.new(2026, 4, 10))

      stats = ExactMatcher.new(@run).call

      assert_equal 3, stats[:source_a_in_window]
      assert_equal 1, stats[:source_a_matched]
      assert_equal 1, stats[:source_a_exceptions]
      assert_equal 1, stats[:source_a_unmatched]
      assert_equal stats[:source_a_in_window],
                   stats[:source_a_matched] + stats[:source_a_exceptions] + stats[:source_a_unmatched]
    end

    test "items already matched/exception in another run are not re-considered" do
      a = make_invoice(external: "inv-1", amount_cents: 1_000, occurred_on: Date.new(2026, 4, 1))
      b = make_bank(external: "bk-1", amount_cents: 1_000, occurred_on: Date.new(2026, 4, 1))
      a.update!(status: "matched")
      b.update!(status: "matched")

      stats = ExactMatcher.new(@run).call
      assert_equal 0, stats[:source_a_in_window]
      assert_equal 0, stats[:matches_created]
    end

    test "preconditions: raises if source_a == source_b" do
      @run.update!(source_a: @source_b, source_b: @source_b)
      assert_raises(ArgumentError) { ExactMatcher.new(@run).call }
    end

    test "preconditions: raises if source_a is not accounting" do
      @source_a.update!(kind: "bank")
      err = assert_raises(ArgumentError) { ExactMatcher.new(@run).call }
      assert_match(/source_a\.kind must be 'accounting'/, err.message)
    end

    test "preconditions: raises if source_b is not bank" do
      @source_b.update!(kind: "accounting")
      err = assert_raises(ArgumentError) { ExactMatcher.new(@run).call }
      assert_match(/source_b\.kind must be 'bank'/, err.message)
    end

    test "preconditions: raises if source_a workspace differs from run workspace" do
      other_workspace = Workspace.create!(name: "Other", slug: "other-#{SecureRandom.hex(4)}", base_currency: "AUD")
      @source_a.update!(workspace: other_workspace)
      err = assert_raises(ArgumentError) { ExactMatcher.new(@run).call }
      assert_match(/source_a belongs to workspace/, err.message)
    end

    test "rerunning the matcher after a successful match is a no-op" do
      make_invoice(external: "inv-1", amount_cents: 1_000, occurred_on: Date.new(2026, 4, 1))
      make_bank(external: "bk-1", amount_cents: 1_000, occurred_on: Date.new(2026, 4, 1))

      ExactMatcher.new(@run).call
      assert_no_difference [ "Match.count", "MatchLeg.count" ] do
        stats = ExactMatcher.new(@run).call
        # After the first run both items are "proposed", not "unmatched",
        # so they no longer enter source_a_in_window.
        assert_equal 0, stats[:source_a_in_window]
      end
    end

    private

    def make_invoice(external:, amount_cents:, occurred_on:, currency: "AUD")
      invoice = Invoice.create!(
        workspace: @workspace,
        invoice_number: external,
        issue_date: occurred_on,
        total_cents: amount_cents.abs,
        currency: currency,
        status: "open"
      )
      ReconcilableItem.create!(
        workspace: @workspace,
        data_source: @source_a,
        import_batch: @batch_a,
        item: invoice,
        amount_cents: amount_cents,
        amount_currency: currency,
        occurred_on: occurred_on,
        external_id: external,
        external_id_hash: Digest::SHA256.hexdigest("#{@source_a.id}:#{external}"),
        status: "unmatched"
      )
    end

    def make_bank(external:, amount_cents:, occurred_on:, currency: "AUD")
      bank = BankTransaction.create!(
        workspace: @workspace,
        posted_date: occurred_on,
        txn_type: amount_cents >= 0 ? "credit" : "debit"
      )
      ReconcilableItem.create!(
        workspace: @workspace,
        data_source: @source_b,
        import_batch: @batch_b,
        item: bank,
        amount_cents: amount_cents,
        amount_currency: currency,
        occurred_on: occurred_on,
        external_id: external,
        external_id_hash: Digest::SHA256.hexdigest("#{@source_b.id}:#{external}"),
        status: "unmatched"
      )
    end
  end
end
