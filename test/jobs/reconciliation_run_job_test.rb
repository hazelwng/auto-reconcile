require "test_helper"

class ReconciliationRunJobTest < ActiveJob::TestCase
  setup do
    @workspace = workspaces(:demo)
    @user = users(:hazel)
    @source_a = data_sources(:demo_invoices)
    @source_b = data_sources(:demo_bank)
    @run = ReconciliationRun.create!(
      workspace: @workspace,
      triggered_by_user: @user,
      source_a: @source_a,
      source_b: @source_b,
      date_range_start: Date.new(2026, 4, 1),
      date_range_end: Date.new(2026, 4, 30),
      status: "queued"
    )
  end

  test "happy path: matcher succeeds -> run is complete with stats and completed_at" do
    ReconciliationRunJob.new.perform(@run.id)

    @run.reload
    assert_equal "complete", @run.status
    assert_not_nil @run.started_at
    assert_not_nil @run.completed_at
    assert_nil @run.error_message
    # No items in fixtures -> empty window, all-zero stats.
    # jsonb persists symbol keys as strings; assert via string keys.
    assert_equal 0, @run.stats["source_a_in_window"]
    assert_equal 0, @run.stats["matches_created"]
  end

  test "matcher raises -> run is failed with error_message, exception re-raised" do
    # Force the matcher to raise by pointing source_a at a non-accounting source.
    @source_a.update!(kind: "bank")

    err = assert_raises(ArgumentError) do
      ReconciliationRunJob.new.perform(@run.id)
    end
    assert_match(/source_a\.kind must be 'accounting'/, err.message)

    @run.reload
    assert_equal "failed", @run.status
    assert_match(/ArgumentError:.*source_a\.kind/, @run.error_message)
    assert_not_nil @run.completed_at
  end

  test "lifecycle reset: a stale failed run is cleaned up before the matcher runs again" do
    # Simulate a previous failed run leaving stale fields on the row.
    @run.update!(
      status: "failed",
      started_at: 1.hour.ago,
      completed_at: 30.minutes.ago,
      error_message: "PrevError: stale message",
      stats: { "matches_created" => 99 }
    )

    # Swap in a stub matcher that captures run state at the moment it is
    # invoked, so we can prove the reset happens BEFORE the matcher runs.
    captured = nil
    stub_class = Class.new do
      define_method(:initialize) { |run| @run = run }
      define_method(:call) do
        reloaded = ReconciliationRun.find(@run.id)
        captured = {
          status: reloaded.status,
          completed_at: reloaded.completed_at,
          error_message: reloaded.error_message,
          stats: reloaded.stats
        }
        { source_a_in_window: 0, matches_created: 0 }
      end
    end

    original = Matchers::ExactMatcher
    Matchers.send(:remove_const, :ExactMatcher)
    Matchers.const_set(:ExactMatcher, stub_class)
    begin
      ReconciliationRunJob.new.perform(@run.id)
    ensure
      Matchers.send(:remove_const, :ExactMatcher)
      Matchers.const_set(:ExactMatcher, original)
    end

    assert_equal "running",    captured[:status]
    assert_nil                 captured[:completed_at]
    assert_nil                 captured[:error_message]
    assert_equal({},           captured[:stats])

    @run.reload
    assert_equal "complete", @run.status
    assert_not_nil @run.completed_at
  end
end
