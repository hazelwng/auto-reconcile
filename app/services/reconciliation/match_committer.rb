module Reconciliation
  class MatchCommitter
    def initialize(reconciliation_run)
      @run = reconciliation_run
      @workspace = reconciliation_run.workspace
    end

    def commit_exact_candidate(candidate)
      with_locked_items(candidate.item_ids) do |items_by_id|
        a = items_by_id.fetch(candidate.source_a_item_id)
        b = items_by_id.fetch(candidate.source_b_item_id)

        commit_exact_match(a, b)
        { kind: :matched }
      end
    end

    def commit_ambiguity(group)
      with_locked_items(group.item_ids) do |items_by_id|
        commit_ambiguity_group(group, items_by_id.values)
        {
          kind: :ambiguous,
          items_count: group.items_count,
          source_a_count: group.source_a_count
        }
      end
    end

    private

    def with_locked_items(item_ids)
      ReconcilableItem.transaction do
        locked_items = item_ids.sort.map { |id| ReconcilableItem.lock.find(id) }
        return { kind: :skipped } if locked_items.any? { |item| item.status != "unmatched" }

        yield locked_items.index_by(&:id)
      end
    end

    def commit_exact_match(a, b)
      match = Match.create!(
        reconciliation_run: @run,
        workspace: @workspace,
        method: "exact",
        status: "proposed",
        confidence: 1.0,
        reasoning: "Exact match: amount #{format_money(a)}, " \
                   "A (invoice) #{a.occurred_on} → B (bank) #{b.occurred_on}"
      )
      MatchLeg.create!(
        match: match,
        reconcilable_item: a,
        side: "a",
        allocated_amount_cents: a.amount_cents.abs,
        allocated_currency: a.amount_currency
      )
      MatchLeg.create!(
        match: match,
        reconcilable_item: b,
        side: "b",
        allocated_amount_cents: b.amount_cents.abs,
        allocated_currency: b.amount_currency
      )
      a.update!(status: "proposed")
      b.update!(status: "proposed")
    end

    def commit_ambiguity_group(group, items)
      group_key = SecureRandom.uuid
      metadata = group.metadata(group_key: group_key)

      items.each do |item|
        ReconciliationException.create!(
          reconciliation_run: @run,
          workspace: @workspace,
          reconcilable_item: item,
          category: "duplicate",
          metadata: metadata
        )
        item.update!(status: "exception")
      end
    end

    def format_money(item)
      "#{item.amount_currency} #{format('%.2f', item.amount_cents.abs / 100.0)}"
    end
  end
end
