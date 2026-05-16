require "set"

module Matchers
  # Builds exact 1:1 matches between source_a (accounting/AR invoices) and
  # source_b (bank transactions) for a given ReconciliationRun.
  #
  # Candidate filter (A is invoice, B is bank):
  #   - both items belong to run.workspace
  #   - a.data_source_id == run.source_a_id
  #   - b.data_source_id == run.source_b_id
  #   - both items are "unmatched"
  #   - a.amount_cents == b.amount_cents (sign already normalized at import)
  #   - a.amount_currency == b.amount_currency
  #   - a.occurred_on in run.date_range_start..run.date_range_end
  #   - b.occurred_on >= a.occurred_on and b.occurred_on <= a.occurred_on + 7 days
  #
  # Uniqueness rule (bidirectional): a candidate edge (A, B) becomes a match
  # only if its connected component in the bipartite candidate graph is
  # exactly one A and one B. Any other component shape is an ambiguity
  # group; every involved item becomes an exception with category "duplicate"
  # and metadata { group_key, subcategory: "ambiguity", reason,
  # involved_item_ids, source_a_item_ids, source_b_item_ids }.
  #
  # Concurrency: each component is processed in its own transaction, with
  # the involved items locked via SELECT FOR UPDATE in ascending id order
  # (deadlock-safe). Status is re-checked under the lock; if any item has
  # been touched by another worker, the component is skipped.
  class ExactMatcher
    BANK_DATE_WINDOW_DAYS = 7

    def initialize(reconciliation_run)
      @run = reconciliation_run
      @workspace = reconciliation_run.workspace
    end

    def call
      validate_run!
      stats = empty_stats
      a_items = source_a_items
      stats[:source_a_in_window] = a_items.size
      return stats if a_items.empty?

      edges = build_candidate_edges(a_items)
      stats[:candidates_evaluated] = edges.size

      connected_components(edges).each do |component_ids|
        result = process_component(component_ids)
        case result[:kind]
        when :matched
          stats[:matches_created]     += 1
          stats[:source_a_matched]    += 1
        when :ambiguous
          stats[:ambiguity_groups_created] += 1
          stats[:exceptions_created]       += result[:items_count]
          stats[:source_a_exceptions]      += result[:source_a_count]
        end
      end

      stats[:source_a_unmatched] = stats[:source_a_in_window] -
                                   stats[:source_a_matched] -
                                   stats[:source_a_exceptions]
      stats
    end

    private

    # Fail fast on misconfigured runs. These are programmer/operator errors,
    # not data errors, so we raise rather than silently producing nonsense.
    def validate_run!
      if @run.source_a_id == @run.source_b_id
        raise ArgumentError, "source_a and source_b must differ (both are data_source ##{@run.source_a_id})"
      end
      unless @run.source_a.workspace_id == @run.workspace_id
        raise ArgumentError, "source_a belongs to workspace ##{@run.source_a.workspace_id}, run is in workspace ##{@run.workspace_id}"
      end
      unless @run.source_b.workspace_id == @run.workspace_id
        raise ArgumentError, "source_b belongs to workspace ##{@run.source_b.workspace_id}, run is in workspace ##{@run.workspace_id}"
      end
      unless @run.source_a.kind == "accounting"
        raise ArgumentError, "source_a.kind must be 'accounting' (got #{@run.source_a.kind.inspect})"
      end
      unless @run.source_b.kind == "bank"
        raise ArgumentError, "source_b.kind must be 'bank' (got #{@run.source_b.kind.inspect})"
      end
    end

    def empty_stats
      {
        candidates_evaluated: 0,
        matches_created: 0,
        exceptions_created: 0,
        ambiguity_groups_created: 0,
        source_a_in_window: 0,
        source_a_matched: 0,
        source_a_exceptions: 0,
        source_a_unmatched: 0
      }
    end

    def source_a_items
      ReconcilableItem.where(
        workspace_id: @run.workspace_id,
        data_source_id: @run.source_a_id,
        status: "unmatched",
        occurred_on: @run.date_range_start..@run.date_range_end
      ).to_a
    end

    # Returns Array of [a_id, b_id] pairs. One query per A is fine for v1
    # volumes; if this becomes hot, a single SQL with a self-join on
    # (amount_cents, amount_currency) + date window would replace it.
    def build_candidate_edges(a_items)
      edges = []
      a_items.each do |a|
        b_ids = ReconcilableItem
          .where(
            workspace_id: @run.workspace_id,
            data_source_id: @run.source_b_id,
            status: "unmatched",
            amount_cents: a.amount_cents,
            amount_currency: a.amount_currency,
            occurred_on: a.occurred_on..(a.occurred_on + BANK_DATE_WINDOW_DAYS.days)
          )
          .pluck(:id)
        b_ids.each { |b_id| edges << [ a.id, b_id ] }
      end
      edges
    end

    def connected_components(edges)
      adj = Hash.new { |h, k| h[k] = [] }
      edges.each do |a, b|
        adj[a] << b
        adj[b] << a
      end

      visited = Set.new
      components = []
      adj.keys.sort.each do |start|
        next if visited.include?(start)
        component = []
        queue = [ start ]
        while (node = queue.shift)
          next if visited.include?(node)
          visited << node
          component << node
          adj[node].each { |n| queue << n unless visited.include?(n) }
        end
        components << component.sort
      end
      components
    end

    def process_component(item_ids)
      ReconcilableItem.transaction do
        locked = item_ids.sort.map { |id| ReconcilableItem.lock.find(id) }
        return { kind: :skipped } if locked.any? { |i| i.status != "unmatched" }

        a_items = locked.select { |i| i.data_source_id == @run.source_a_id }
        b_items = locked.select { |i| i.data_source_id == @run.source_b_id }

        if a_items.size == 1 && b_items.size == 1
          commit_exact_match(a_items.first, b_items.first)
          { kind: :matched }
        else
          commit_ambiguity(locked)
          {
            kind: :ambiguous,
            items_count: locked.size,
            source_a_count: a_items.size
          }
        end
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

    def commit_ambiguity(items)
      group_key = SecureRandom.uuid
      a_items = items.select { |i| i.data_source_id == @run.source_a_id }
      b_items = items.select { |i| i.data_source_id == @run.source_b_id }
      all_ids = items.map(&:id)
      a_ids = a_items.map(&:id)
      b_ids = b_items.map(&:id)
      reason = ambiguity_reason(a_items.size, b_items.size)

      items.each do |item|
        ReconciliationException.create!(
          reconciliation_run: @run,
          workspace: @workspace,
          reconcilable_item: item,
          category: "duplicate",
          metadata: {
            "group_key"          => group_key,
            "subcategory"        => "ambiguity",
            "reason"             => reason,
            "involved_item_ids"  => all_ids,
            "source_a_item_ids"  => a_ids,
            "source_b_item_ids"  => b_ids
          }
        )
        item.update!(status: "exception")
      end
    end

    def ambiguity_reason(a_count, b_count)
      if a_count == 1
        "1 invoice with #{b_count} bank candidates"
      elsif b_count == 1
        "#{a_count} invoices with 1 bank candidate"
      else
        "#{a_count} invoices with #{b_count} bank candidates (overlapping)"
      end
    end

    def format_money(item)
      "#{item.amount_currency} #{format('%.2f', item.amount_cents.abs / 100.0)}"
    end
  end
end
