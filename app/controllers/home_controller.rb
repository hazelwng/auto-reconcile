class HomeController < ApplicationController
  def index
    @bank_source       = current_workspace.default_data_source("bank")
    @accounting_source = current_workspace.default_data_source("accounting")
    @period_opts       = current_workspace.period_options
    @last_bank_batch       = @bank_source.import_batches.order(created_at: :desc).first
    @last_accounting_batch = @accounting_source.import_batches.order(created_at: :desc).first
    @last_run = current_workspace.reconciliation_runs.order(created_at: :desc).first
  end

  def reconcile
    bank       = current_workspace.default_data_source("bank")
    accounting = current_workspace.default_data_source("accounting")
    period_opts = current_workspace.period_options

    start_date, end_date = resolve_period(period_opts)

    if start_date.nil?
      redirect_to root_path, alert: "Upload both files before running reconciliation." and return
    end

    run = ReconciliationRun.create!(
      workspace:           current_workspace,
      triggered_by_user:   current_user,
      source_a:            accounting,
      source_b:            bank,
      date_range_start:    start_date,
      date_range_end:      end_date,
      status:              "queued",
      stats:               {}
    )

    ReconciliationRunJob.perform_later(run.id)
    redirect_to reconciliation_run_path(run)
  end

  def reset
    ws = current_workspace
    Match.where(workspace: ws).destroy_all
    ReconciliationException.where(workspace: ws).destroy_all
    ReconciliationRun.where(workspace: ws).destroy_all
    ReconcilableItem.with_discarded.where(workspace: ws).destroy_all
    ImportBatch.joins(:data_source).where(data_sources: { workspace_id: ws.id }).destroy_all
    redirect_to root_path, notice: "Demo data cleared."
  end

  private

  def resolve_period(period_opts)
    id = params[:period_id].presence || period_opts.default_id
    return [ nil, nil ] if id.nil?
    period_opts.find_range(id) || [ period_opts.min, period_opts.max ]
  end
end
