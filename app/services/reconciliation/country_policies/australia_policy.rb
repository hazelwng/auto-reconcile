module Reconciliation
  module CountryPolicies
    class AustraliaPolicy < DefaultPolicy
      LEGAL_SUFFIX_PATTERN = /(?:proprietarylimited|ptyltd|limited|ltd)\z/

      def normalize_party_name(raw)
        PartyNormalizer.latin(raw).sub(LEGAL_SUFFIX_PATTERN, "")
      end

      def party_match_score(invoice:, bank_transaction:)
        invoice_name = normalize_party_name(invoice&.payer)
        bank_name = normalize_party_name(bank_transaction&.counterparty)
        return 0.0 if invoice_name.blank? || bank_name.blank?

        invoice_name == bank_name ? 1.0 : 0.0
      end

      def explain_party_match(invoice:, bank_transaction:)
        return nil unless party_match_score(invoice: invoice, bank_transaction: bank_transaction).positive?

        "latin-normalized party match"
      end
    end
  end
end
