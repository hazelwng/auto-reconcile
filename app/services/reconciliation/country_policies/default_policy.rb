module Reconciliation
  module CountryPolicies
    class DefaultPolicy
      ONE_CENT_CONFIDENCE = 0.85
      WIDER_AMOUNT_CONFIDENCE = 0.70

      def exact_tolerances
        {
          amount_cents: 0,
          amount_percent: 0.0,
          amount_percent_cap_cents: 0,
          bank_date_window_start_days: 0,
          bank_date_window_end_days: 7,
          method: "exact",
          confidence_resolver: ->(_amount_delta_cents) { 1.0 }
        }
      end

      def heuristic_tolerances
        {
          amount_cents: 1,
          amount_percent: 0.005,
          amount_percent_cap_cents: 500,
          bank_date_window_start_days: -2,
          bank_date_window_end_days: 14,
          method: "heuristic",
          confidence_resolver: method(:heuristic_confidence_for)
        }
      end

      private

      def heuristic_confidence_for(amount_delta_cents)
        return ONE_CENT_CONFIDENCE if amount_delta_cents <= 1

        WIDER_AMOUNT_CONFIDENCE
      end
    end
  end
end
