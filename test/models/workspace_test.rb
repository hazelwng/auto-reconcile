require "test_helper"

class WorkspaceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:demo)
    @user      = users(:hazel)
  end

  # ------------------------------------------------------------------
  # default_data_source
  # ------------------------------------------------------------------

  test "default_data_source returns existing kept bank source when present" do
    existing = @workspace.data_sources.kept.find_by(kind: "bank")
    assert_not_nil existing, "fixture should provide an existing bank source"

    assert_equal existing, @workspace.default_data_source("bank")
  end

  test "default_data_source creates canonical-named source when none exists for kind" do
    @workspace.data_sources.where(kind: "accounting").each(&:destroy)
    assert_equal 0, @workspace.data_sources.kept.where(kind: "accounting").count

    created = nil
    assert_difference -> { @workspace.data_sources.count } => 1 do
      created = @workspace.default_data_source("accounting")
    end

    assert_equal "Invoices", created.name
    assert_equal "accounting", created.kind
    assert_equal @workspace.base_currency, created.currency
    assert_equal({}, created.schema_mapping)
  end

  test "default_data_source ignores discarded sources and creates a fresh one" do
    @workspace.data_sources.where(kind: "bank").each(&:discard)
    assert_equal 0, @workspace.data_sources.kept.where(kind: "bank").count

    created = @workspace.default_data_source("bank")
    assert created.kept?
    assert_equal "Bank", created.name
    assert_equal "bank", created.kind
  end

  test "default_data_source raises for unsupported kind" do
    assert_raises(ArgumentError) { @workspace.default_data_source("stripe") }
  end

  # ------------------------------------------------------------------
  # period_options
  # ------------------------------------------------------------------

  test "period_options returns empty result when workspace has no items" do
    @workspace.reconcilable_items.destroy_all
    result = @workspace.period_options

    assert_empty result.options
    assert_nil result.default_id
    assert_nil result.min
    assert_nil result.max
  end

  test "period_options returns single month without an All option" do
    @workspace.reconcilable_items.destroy_all
    seed_items(@workspace, [ Date.new(2025, 10, 5), Date.new(2025, 10, 14), Date.new(2025, 10, 31) ])

    result = @workspace.period_options
    assert_equal 1, result.options.size
    assert_equal "2025-10", result.options.first[:id]
    assert_equal "Oct 2025", result.options.first[:label]
    assert_equal "2025-10", result.default_id
    refute result.options.any? { |o| o[:id] == "all" }
  end

  test "period_options sorts months newest first and adds All option when spanning multiple months" do
    @workspace.reconcilable_items.destroy_all
    seed_items(@workspace, [
      Date.new(2025, 9, 10),
      Date.new(2025, 10, 1),
      Date.new(2025, 10, 20),
      Date.new(2025, 11, 3)
    ])

    result = @workspace.period_options
    ids = result.options.map { |o| o[:id] }
    assert_equal [ "2025-11", "2025-10", "2025-09", "all" ], ids

    assert_equal "2025-11", result.default_id
    assert_equal Date.new(2025, 9, 10), result.min
    assert_equal Date.new(2025, 11, 3), result.max
  end

  test "period_options ignores discarded items" do
    @workspace.reconcilable_items.destroy_all
    seed_items(@workspace, [ Date.new(2025, 9, 5), Date.new(2025, 10, 10) ])
    @workspace.reconcilable_items.where(occurred_on: Date.new(2025, 10, 10)).each(&:discard)

    result = @workspace.period_options
    ids = result.options.map { |o| o[:id] }
    assert_equal [ "2025-09" ], ids
    assert_equal "2025-09", result.default_id
  end

  # ------------------------------------------------------------------
  # PeriodOptions#find_range
  # ------------------------------------------------------------------

  test "PeriodOptions#find_range returns month bounds for a month id" do
    @workspace.reconcilable_items.destroy_all
    seed_items(@workspace, [ Date.new(2025, 10, 5), Date.new(2025, 11, 3) ])

    result = @workspace.period_options
    start_date, end_date = result.find_range("2025-10")
    assert_equal Date.new(2025, 10, 1), start_date
    assert_equal Date.new(2025, 10, 31), end_date
  end

  test "PeriodOptions#find_range returns full span for the 'all' id" do
    @workspace.reconcilable_items.destroy_all
    seed_items(@workspace, [ Date.new(2025, 9, 10), Date.new(2025, 11, 3) ])

    result = @workspace.period_options
    start_date, end_date = result.find_range("all")
    assert_equal Date.new(2025, 9, 10), start_date
    assert_equal Date.new(2025, 11, 3), end_date
  end

  test "PeriodOptions#find_range returns nil for an unknown id" do
    @workspace.reconcilable_items.destroy_all
    seed_items(@workspace, [ Date.new(2025, 10, 5) ])

    result = @workspace.period_options
    assert_nil result.find_range("2099-01")
  end

  private

  # Builds bare-minimum BankTransaction-backed ReconcilableItems on the given
  # dates. The matcher and view don't care about extra fields for these
  # tests; we just need rows with workspace_id, data_source_id, occurred_on,
  # amount_cents, amount_currency, status, external_id_hash.
  def seed_items(workspace, dates)
    bank_source = workspace.default_data_source("bank")
    batch = workspace.import_batches.where(data_source: bank_source).first ||
            bank_source.import_batches.create!(status: "complete", user: @user)

    dates.each_with_index do |d, i|
      txn = BankTransaction.create!(
        workspace: workspace,
        posted_date: d,
        txn_type: "credit",
        counterparty: "Test Co",
        memo: "test",
        raw_payload: {}
      )
      ReconcilableItem.create!(
        workspace: workspace,
        data_source: bank_source,
        import_batch: batch,
        item: txn,
        amount_cents: 100_00,
        amount_currency: "USD",
        occurred_on: d,
        description: "test",
        external_id: "test-#{d}-#{i}",
        external_id_hash: "test-hash-#{d}-#{i}",
        status: "unmatched"
      )
    end
  end
end
