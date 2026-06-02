module Reconciliation
  class HeuristicTier
    def initialize(reconciliation_run, policy:)
      @run = reconciliation_run
      @policy = policy
    end

    def call
      candidate_result = CandidateFinder.new(@run, tolerances: @policy.heuristic_tolerances).call
      candidates = with_supporting_evidence(candidate_result.candidates)
      uniqueness_result = UniquenessChecker.new(candidates).call

      TierResult.new(
        unique_candidates: uniqueness_result.unique_candidates,
        ambiguous_groups: uniqueness_result.ambiguous_groups,
        source_a_count: candidate_result.source_a_count,
        candidates_evaluated: candidate_result.candidates.size
      )
    end

    private

    def with_supporting_evidence(candidates)
      items_by_id = items_by_id_for(candidates)

      candidates.filter_map do |candidate|
        a = items_by_id.fetch(candidate.source_a_item_id)
        b = items_by_id.fetch(candidate.source_b_item_id)
        invoice = a.item if a.item.is_a?(Invoice)
        bank_transaction = b.item if b.item.is_a?(BankTransaction)

        score = @policy.party_match_score(invoice: invoice, bank_transaction: bank_transaction)
        next candidate if score.nil?

        fragments = supporting_evidence_fragments(invoice, bank_transaction, b, score)
        next if fragments.empty?

        Candidate.new(
          source_a_item_id: candidate.source_a_item_id,
          source_b_item_id: candidate.source_b_item_id,
          matched_on: candidate.matched_on.merge(
            party_match_score: score,
            reasoning_fragments: fragments
          )
        )
      end
    end

    def items_by_id_for(candidates)
      item_ids = candidates.flat_map(&:item_ids).uniq
      return {} if item_ids.empty?

      ReconcilableItem.includes(:item).where(id: item_ids).index_by(&:id)
    end

    def supporting_evidence_fragments(invoice, bank_transaction, bank_item, party_score)
      fragments = []

      if party_score.positive?
        fragments << @policy.explain_party_match(invoice: invoice, bank_transaction: bank_transaction)
      end

      matching_reference_tokens(invoice, bank_transaction, bank_item).each do |token|
        fragments << "reference #{token} in bank memo"
      end

      fragments.compact
    end

    def matching_reference_tokens(invoice, bank_transaction, bank_item)
      invoice_number = invoice&.invoice_number.to_s
      return [] if invoice_number.blank?

      invoice_tokens = ([ invoice_number.upcase ] + @policy.reference_tokens(invoice_number)).uniq
      bank_tokens = [
        bank_transaction&.memo,
        bank_transaction&.counterparty,
        bank_item&.description
      ].flat_map { |text| @policy.reference_tokens(text) }.uniq

      invoice_tokens & bank_tokens
    end
  end
end
