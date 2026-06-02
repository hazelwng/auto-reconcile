module Reconciliation
  module CountryPolicies
    class DefaultPolicy
      ONE_CENT_CONFIDENCE = 0.85
      WIDER_AMOUNT_CONFIDENCE = 0.70
      INV_TOKEN_PATTERN = /\bINV-[A-Z]{2}-\d+\b/i
      LABELED_REF_PATTERN = /\b(?:Invoice|Ref)[:\s#]+([A-Z0-9-]+)\b/i

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

      def normalize_party_name(raw)
        PartyNormalizer.latin(raw)
      end

      def reference_tokens(text)
        tokens = text.to_s.scan(INV_TOKEN_PATTERN).map(&:upcase)
        tokens.concat(text.to_s.scan(LABELED_REF_PATTERN).flatten.map(&:upcase))
        tokens.uniq
      end

      def party_match_score(invoice:, bank_transaction:)
        nil
      end

      def explain_party_match(invoice:, bank_transaction:)
        nil
      end

      private

      def heuristic_confidence_for(amount_delta_cents)
        return ONE_CENT_CONFIDENCE if amount_delta_cents <= 1

        WIDER_AMOUNT_CONFIDENCE
      end
    end
  end
end
