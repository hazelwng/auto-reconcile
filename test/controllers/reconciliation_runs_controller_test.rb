require "test_helper"

class ReconciliationRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace  = workspaces(:demo)
    @user       = users(:hazel)
    @accounting = data_sources(:demo_invoices)
    @bank       = data_sources(:demo_bank)
  end

  test "GET /reconciliation_runs/new renders form with both source selects" do
    get new_reconciliation_run_path
    assert_response :success
    assert_match "Run reconciliation", response.body
    assert_match @accounting.name, response.body
    assert_match @bank.name, response.body
  end

  test "POST with valid params creates run and enqueues ReconciliationRunJob" do
    assert_difference -> { ReconciliationRun.count } => 1,
                      -> { enqueued_jobs.size }    => 1 do
      post reconciliation_runs_path, params: {
        reconciliation_run: {
          source_a_id: @accounting.id,
          source_b_id: @bank.id,
          date_range_start: "2026-04-01",
          date_range_end:   "2026-04-30"
        }
      }
    end

    run = ReconciliationRun.last
    assert_redirected_to reconciliation_run_path(run)
    assert_equal "queued", run.status
    assert_equal @workspace.id, run.workspace_id
    assert_equal @user.id, run.triggered_by_user_id
    assert_equal "ReconciliationRunJob", enqueued_jobs.last["job_class"]
    assert_equal [ run.id ], enqueued_jobs.last["arguments"]
  end

  test "POST without source_a_id re-renders new with an error" do
    assert_no_difference [ "ReconciliationRun.count", "enqueued_jobs.size" ] do
      post reconciliation_runs_path, params: {
        reconciliation_run: {
          source_a_id: "",
          source_b_id: @bank.id,
          date_range_start: "2026-04-01",
          date_range_end:   "2026-04-30"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match(/must be an accounting source/, response.body)
  end

  test "POST without source_b_id re-renders new with an error" do
    assert_no_difference [ "ReconciliationRun.count", "enqueued_jobs.size" ] do
      post reconciliation_runs_path, params: {
        reconciliation_run: {
          source_a_id: @accounting.id,
          source_b_id: "",
          date_range_start: "2026-04-01",
          date_range_end:   "2026-04-30"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match(/must be a bank source/, response.body)
  end

  test "POST with end-before-start re-renders new with a validation error" do
    assert_no_difference [ "ReconciliationRun.count", "enqueued_jobs.size" ] do
      post reconciliation_runs_path, params: {
        reconciliation_run: {
          source_a_id: @accounting.id,
          source_b_id: @bank.id,
          date_range_start: "2026-04-30",
          date_range_end:   "2026-04-01"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match(/must be on or after start/, response.body)
  end

  test "POST treats a cross-workspace source_a_id as missing (defence-in-depth)" do
    other_ws = Workspace.create!(name: "Other", slug: "other-#{SecureRandom.hex(4)}", base_currency: "AUD")
    foreign_accounting = DataSource.create!(workspace: other_ws, name: "Other Books", kind: "accounting", currency: "AUD")

    assert_no_difference [ "ReconciliationRun.count", "enqueued_jobs.size" ] do
      post reconciliation_runs_path, params: {
        reconciliation_run: {
          source_a_id: foreign_accounting.id,
          source_b_id: @bank.id,
          date_range_start: "2026-04-01",
          date_range_end:   "2026-04-30"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match(/must be an accounting source/, response.body)
  end

  test "POST rejects a same-workspace bank source for source_a (kind enforcement)" do
    # The form's dropdown filters by kind, but a direct POST could bypass it.
    # Controller must enforce the kind invariant so we don't enqueue a run that
    # is guaranteed to fail inside ExactMatcher#validate_run!.
    assert_no_difference [ "ReconciliationRun.count", "enqueued_jobs.size" ] do
      post reconciliation_runs_path, params: {
        reconciliation_run: {
          source_a_id: @bank.id,
          source_b_id: @bank.id,
          date_range_start: "2026-04-01",
          date_range_end:   "2026-04-30"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match(/must be an accounting source/, response.body)
  end

  test "POST rejects a same-workspace accounting source for source_b (kind enforcement)" do
    assert_no_difference [ "ReconciliationRun.count", "enqueued_jobs.size" ] do
      post reconciliation_runs_path, params: {
        reconciliation_run: {
          source_a_id: @accounting.id,
          source_b_id: @accounting.id,
          date_range_start: "2026-04-01",
          date_range_end:   "2026-04-30"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match(/must be a bank source/, response.body)
  end

  test "GET /reconciliation_runs/:id shows status, stats and section counters" do
    run = ReconciliationRun.create!(
      workspace: @workspace, triggered_by_user: @user,
      source_a: @accounting, source_b: @bank,
      date_range_start: "2026-04-01", date_range_end: "2026-04-30",
      status: "complete",
      started_at: Time.current - 5, completed_at: Time.current,
      stats: {
        "candidates_evaluated"     => 3,
        "matches_created"          => 1,
        "exceptions_created"       => 2,
        "ambiguity_groups_created" => 1,
        "source_a_in_window"       => 3,
        "source_a_matched"         => 1,
        "source_a_exceptions"      => 1,
        "source_a_unmatched"       => 1
      }
    )

    get reconciliation_run_path(run)
    assert_response :success
    assert_match "complete", response.body
    assert_match "Matches", response.body
    assert_match "Exceptions", response.body
    assert_match "Stats", response.body
  end

  test "GET show renders error_message when status=failed" do
    run = ReconciliationRun.create!(
      workspace: @workspace, triggered_by_user: @user,
      source_a: @accounting, source_b: @bank,
      date_range_start: "2026-04-01", date_range_end: "2026-04-30",
      status: "failed",
      error_message: "ArgumentError: source_a.kind must be 'accounting' (got \"bank\")"
    )

    get reconciliation_run_path(run)
    assert_response :success
    assert_match "failed", response.body
    assert_match "source_a.kind must be", response.body
  end

  test "GET show for a run in another workspace 404s" do
    other_ws = Workspace.create!(name: "Other", slug: "other-#{SecureRandom.hex(4)}", base_currency: "AUD")
    other_acct = DataSource.create!(workspace: other_ws, name: "Other Books", kind: "accounting", currency: "AUD")
    other_bank = DataSource.create!(workspace: other_ws, name: "Other Bank",  kind: "bank",       currency: "AUD")
    other_run = ReconciliationRun.create!(
      workspace: other_ws, triggered_by_user: @user,
      source_a: other_acct, source_b: other_bank,
      date_range_start: "2026-04-01", date_range_end: "2026-04-30",
      status: "queued"
    )

    get reconciliation_run_path(other_run)
    assert_response :not_found
  end
end
