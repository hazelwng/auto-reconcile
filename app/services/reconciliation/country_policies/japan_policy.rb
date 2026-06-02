module Reconciliation
  module CountryPolicies
    class JapanPolicy < DefaultPolicy
      CORPORATE_MARKERS = [ "株式会社", "(株)", "有限会社", "(有)" ].freeze

      def normalize_party_name(raw)
        normalized = raw.to_s.unicode_normalize(:nfkc)
        PartyNormalizer.kana(PartyNormalizer.strip_markers(normalized, CORPORATE_MARKERS))
      end

      def party_match_score(invoice:, bank_transaction:)
        invoice_name = normalize_party_name(invoice&.payer_kana)
        bank_name = normalize_party_name(bank_transaction&.counterparty)
        return 0.0 if invoice_name.blank? || bank_name.blank?

        invoice_name == bank_name ? 1.0 : 0.0
      end

      def explain_party_match(invoice:, bank_transaction:)
        return nil unless party_match_score(invoice: invoice, bank_transaction: bank_transaction).positive?

        "kana-normalized party match"
      end
    end
  end
end
