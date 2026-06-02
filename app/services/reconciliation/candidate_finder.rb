module Reconciliation
  class CandidateFinder
    EXACT_TOLERANCES = {
      amount_cents: 0,
      amount_percent: 0.0,
      amount_percent_cap_cents: 0,
      bank_date_window_start_days: 0,
      bank_date_window_end_days: 7,
      method: "exact",
      confidence_resolver: nil
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
        candidate_b_items_for(a).map do |b|
          amount_delta_cents = (a.amount_cents - b.amount_cents).abs
          date_delta_days = (b.occurred_on - a.occurred_on).to_i

          Candidate.new(
            source_a_item_id: a.id,
            source_b_item_id: b.id,
            matched_on: {
              amount_delta_cents: amount_delta_cents,
              amount_currency: a.amount_currency,
              date_delta_days: date_delta_days,
              method: method,
              confidence: confidence_for(amount_delta_cents)
            }
          )
        end
      end
    end

    def candidate_b_items_for(a)
      ReconcilableItem
        .where(
          workspace_id: @run.workspace_id,
          data_source_id: @run.source_b_id,
          status: "unmatched",
          amount_currency: a.amount_currency,
          amount_cents: amount_range_for(a),
          occurred_on: bank_date_range_for(a)
        )
        .to_a
    end

    def amount_range_for(a)
      tolerance = amount_tolerance_for(a.amount_cents)
      (a.amount_cents - tolerance)..(a.amount_cents + tolerance)
    end

    def amount_tolerance_for(amount_cents)
      percent_tolerance = (amount_cents.abs * amount_percent).round
      capped_percent_tolerance = [ percent_tolerance, amount_percent_cap_cents ].min
      [ amount_cents_tolerance, capped_percent_tolerance ].max
    end

    def bank_date_range_for(a)
      (a.occurred_on + bank_date_window_start_days.days)..(a.occurred_on + bank_date_window_end_days.days)
    end

    def confidence_for(amount_delta_cents)
      resolver = @tolerances.fetch(:confidence_resolver)
      return 1.0 unless resolver

      resolver.call(amount_delta_cents)
    end

    def amount_cents_tolerance
      @tolerances.fetch(:amount_cents)
    end

    def amount_percent
      @tolerances.fetch(:amount_percent)
    end

    def amount_percent_cap_cents
      @tolerances.fetch(:amount_percent_cap_cents)
    end

    def bank_date_window_start_days
      @tolerances.fetch(:bank_date_window_start_days)
    end

    def bank_date_window_end_days
      @tolerances.fetch(:bank_date_window_end_days)
    end

    def method
      @tolerances.fetch(:method)
    end
  end
end
