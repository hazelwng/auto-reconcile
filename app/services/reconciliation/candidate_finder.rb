module Reconciliation
  class CandidateFinder
    EXACT_TOLERANCES = {
      bank_date_window_days: 7
    }.freeze

    Result = Data.define(:candidates, :source_a_count)

    def initialize(reconciliation_run, tolerances: {})
      @run = reconciliation_run
      @tolerances = EXACT_TOLERANCES.merge(tolerances)
    end

    def call
      a_items = source_a_items
      Result.new(
        candidates: build_candidates(a_items),
        source_a_count: a_items.size
      )
    end

    private

    def source_a_items
      ReconcilableItem.where(
        workspace_id: @run.workspace_id,
        data_source_id: @run.source_a_id,
        status: "unmatched",
        occurred_on: @run.date_range_start..@run.date_range_end
      ).to_a
    end

    # One query per A is fine for v1 volumes. If this becomes hot, replace
    # with a SQL self-join on amount/currency plus the date window.
    def build_candidates(a_items)
      a_items.flat_map do |a|
        candidate_b_ids_for(a).map do |b_id|
          Candidate.new(
            source_a_item_id: a.id,
            source_b_item_id: b_id,
            matched_on: {
              amount_cents: a.amount_cents,
              amount_currency: a.amount_currency,
              bank_date_window_days: bank_date_window_days
            }
          )
        end
      end
    end

    def candidate_b_ids_for(a)
      ReconcilableItem
        .where(
          workspace_id: @run.workspace_id,
          data_source_id: @run.source_b_id,
          status: "unmatched",
          amount_cents: a.amount_cents,
          amount_currency: a.amount_currency,
          occurred_on: a.occurred_on..(a.occurred_on + bank_date_window_days.days)
        )
        .pluck(:id)
    end

    def bank_date_window_days
      @tolerances.fetch(:bank_date_window_days)
    end
  end
end
