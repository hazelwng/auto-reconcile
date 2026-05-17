class ReconciliationRunsController < ApplicationController
  def new
    @reconciliation_run = ReconciliationRun.new(
      date_range_start: Date.current - 30,
      date_range_end: Date.current
    )
    load_form_options
  end

  def create
    # Enforce kind at the controller — defence-in-depth against direct POSTs that
    # bypass the form's dropdown filtering. Without this, a wrong-kind id would
    # save the run and only fail later inside ExactMatcher#validate_run!.
    source_a = current_workspace.data_sources.find_by(
      id: params.dig(:reconciliation_run, :source_a_id), kind: "accounting"
    )
    source_b = current_workspace.data_sources.find_by(
      id: params.dig(:reconciliation_run, :source_b_id), kind: "bank"
    )

    @reconciliation_run = ReconciliationRun.new(
      workspace: current_workspace,
      triggered_by_user: current_user,
      source_a: source_a,
      source_b: source_b,
      date_range_start: params.dig(:reconciliation_run, :date_range_start),
      date_range_end: params.dig(:reconciliation_run, :date_range_end),
      status: "queued",
      stats: {}
    )

    @reconciliation_run.errors.add(:source_a_id, "must be an accounting source in this workspace") if source_a.nil?
    @reconciliation_run.errors.add(:source_b_id, "must be a bank source in this workspace") if source_b.nil?

    if @reconciliation_run.errors.any?
      load_form_options
      render :new, status: :unprocessable_entity and return
    end

    if @reconciliation_run.save
      ReconciliationRunJob.perform_later(@reconciliation_run.id)
      redirect_to reconciliation_run_path(@reconciliation_run), notice: "Reconciliation run queued."
    else
      load_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @reconciliation_run = ReconciliationRun.find(params[:id])
    raise ActiveRecord::RecordNotFound if @reconciliation_run.workspace_id != current_workspace.id

    @matches = @reconciliation_run.matches
      .includes(match_legs: { reconcilable_item: :data_source })
      .order(:id)
    @exceptions = @reconciliation_run.reconciliation_exceptions
      .includes(reconcilable_item: :data_source)
      .order(:id)
  end

  private

  def load_form_options
    @accounting_sources = current_workspace.data_sources.where(kind: "accounting").order(:name)
    @bank_sources       = current_workspace.data_sources.where(kind: "bank").order(:name)
  end
end
