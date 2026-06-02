require "set"

module Reconciliation
  class UniquenessChecker
    Result = Data.define(:unique_candidates, :ambiguous_groups)

    def initialize(candidates)
      @candidates = candidates
    end

    def call
      unique_candidates = []
      ambiguous_groups = []

      connected_components.each do |component|
        source_a_item_ids = ids_for(component, :a)
        source_b_item_ids = ids_for(component, :b)

        if source_a_item_ids.one? && source_b_item_ids.one?
          unique_candidates << unique_candidate_for(source_a_item_ids.first, source_b_item_ids.first)
        else
          ambiguous_groups << AmbiguityGroup.new(
            source_a_item_ids: source_a_item_ids,
            source_b_item_ids: source_b_item_ids
          )
        end
      end

      Result.new(
        unique_candidates: unique_candidates,
        ambiguous_groups: ambiguous_groups
      )
    end

    private

    def connected_components
      adjacency = Hash.new { |h, k| h[k] = [] }
      @candidates.each do |candidate|
        a_node = [ :a, candidate.source_a_item_id ]
        b_node = [ :b, candidate.source_b_item_id ]
        adjacency[a_node] << b_node
        adjacency[b_node] << a_node
      end

      visited = Set.new
      adjacency.keys.sort_by { |side, id| [ side.to_s, id ] }.filter_map do |start|
        next if visited.include?(start)

        component = []
        queue = [ start ]
        while (node = queue.shift)
          next if visited.include?(node)

          visited << node
          component << node
          adjacency[node].each { |neighbor| queue << neighbor unless visited.include?(neighbor) }
        end

        component
      end
    end

    def ids_for(component, side)
      component.filter_map { |node_side, id| id if node_side == side }.sort
    end

    def unique_candidate_for(source_a_item_id, source_b_item_id)
      @candidates.find do |candidate|
        candidate.source_a_item_id == source_a_item_id &&
          candidate.source_b_item_id == source_b_item_id
      end
    end
  end
end
