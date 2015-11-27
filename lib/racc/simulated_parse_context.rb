require 'racc/directed_graph'
require 'set'

module Racc
  class SimulatedParseContext < ReversibleDirectedGraph
    def self.from_path(grammar, path)
      path.each_with_object(SimulatedParseContext.new(grammar)) do |sym, context|
        if sym.terminal?
          context.shift!(sym)
        else
          context.reduce!(sym)
        end
      end
    end

    def initialize(grammar)
      super(grammar.locations.size)
      @grammar = grammar
      @start   = 0
      add_leaves!(@start, grammar.start.heads)
    end

    def shift!(sym)
      raise 'Can only shift a terminal' unless sym.terminal?
      leaf_ptrs = ptrs(leaves(@start))
      matching  = leaf_ptrs.select { |ptr| !ptr.reduce? && ptr.symbol == sym }
      replace_leaves!(matching.map { |ptr| [parents(ptr.ident), ptr.next] })
    end

    def reduce!(sym)
      raise 'Can only reduce a nonterminal' unless sym.nonterminal?
      all_ptrs = ptrs(reachable(@start))
      matching  = all_ptrs.select { |ptr| !ptr.reduce? && ptr.symbol == sym }
      replace_leaves!(matching.map { |ptr| [parents(ptr.ident), ptr.next] })
    end

    def lookahead!(sym)
      raise 'Lookahead must be a terminal' unless sym.terminal?
      leaf_ptrs  = ptrs(leaves(@start))
      new_leaves = leaf_ptrs.select do |ptr|
        ptr.reduce? ? lookahead_valid_after_reduce?(ptr, sym) : ptr.symbol == sym
      end
      keep_nodes!(new_leaves.map(&:ident))
    end

    # what (sample) sequence of terminals/NTs could lead to a successful parse
    # from here?
    def path_to_success
      dst_ptrs  = @grammar.locations.select { |p| p.reduce? || p.symbol.terminal? }
      dst_nodes = Set.new(dst_ptrs.map(&:ident))
      paths     = all_paths(@start) do |_, node|
        # this cost function helps find the path to a successful parse which
        # can be described most succinctly
        ptr(node).rule.symbols.size - ptr(node).index + 1
      end
      path      = paths.select { |node, path| dst_nodes.include?(node) }
                       .map { |_, path| path }.min_by(&:size)

      # the 'path' we have found is the path from the start symbol, traversing
      # from the RHS of rules which we could use to reach the start symbol, to
      # the LHS of the next NT which we need to reduce to make progress in
      # that rule, until it 'bottoms out' at a rule which does not have an NT
      # coming next

      throw :dead_end if path.nil?

      # don't show the synthesized rule which reduces to the 'dummy' symbol
      # we need to reduce from the lowest level rule on up, so the order
      # also has to be reversed
      # all rules except for the first start with the NT which the previous
      # rule had just reduced; don't show that (it's redundant)
      ptrs(path.drop(1).reverse).each_with_index.flat_map do |ptr, i|
        ptr = ptr.next unless i == 0
        ptr.rule.symbols[ptr.index..-1] << "(reduce to #{ptr.rule.target})"
      end
    end

    def to_s
      active_ptrs = ptrs(reachable(@start).delete(0))
      active_ptrs.sort_by(&:ident).map(&:to_s).join("\n")
    end

    def dup
      grammar, start = @grammar, @start
      super.tap { |spc| spc.instance_eval { @grammar = grammar; @start = start }}
    end

    private

    def ptrs(nodes)
      nodes.map { |i| @grammar.locations[i] } # could also use `values_at`
    end

    def ptr(node)
      @grammar.locations[node]
    end

    def add_leaves!(parent, ptrs)
      ptrs.each { |ptr| add_child(parent, ptr.ident) }
      Racc.set_closure(ptrs) do |ptr|
        if sym = ptr.symbol
          sym.heads.each { |other| add_child(ptr.ident, other.ident) }
        end
      end
    end

    def add_leaf!(parents, ptr)
      parents.each { |parent| add_child(parent, ptr.ident) }
      Racc.set_closure([ptr]) do |ptr|
        if sym = ptr.symbol
          sym.heads.each { |other| add_child(ptr.ident, other.ident) }
        end
      end
    end

    def keep_nodes!(nodes)
      dead = reachable(@start) - can_reach(nodes) - reachable_from(nodes)
      dead.each { |node| remove_node(node) }
      self
    end

    def replace_leaves!(new_leaves)
      new_leaves.each { |parents, ptr| add_leaf!(parents, ptr) }
      nodes = new_leaves.map { |_, ptr| ptr.ident }
      keep_nodes!(nodes)
    end

    def lookahead_valid_after_reduce?(rptr, sym)
      Racc.set_closure(ptrs_after_reduce(rptr)) do |ptr|
        if ptr.reduce?
          ptrs_after_reduce(ptr)
        elsif ptr.symbol.terminal?
          return true if ptr.symbol == sym
        else
          ptr.symbol.heads
        end
      end
      false
    end

    def ptrs_after_reduce(ptr)
      ptrs(parents(ptr.ident)).map(&:next)
    end
  end
end