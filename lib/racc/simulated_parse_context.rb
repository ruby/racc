require 'racc/directed_graph'
require 'set'

module Racc
  # Tree structure which describes the entire context, from top down, of a
  # (simulated) in-progress parse
  # What rules could we be "in" at a certain point in the parsing process?
  class SimulatedParseContext < Graph::Generic
    class Node < Graph::Node
      def initialize(ptr)
        super()
        @ptr = ptr
      end

      attr_reader :ptr

      # all nodes on this graph have only one parent node (it's a tree)
      def parent
        raise 'Should have 1 parent' unless self.in.one?
        self.in.first
      end

      def ancestors
        # don't include the "dummy" start node which does not contain a valid
        # LocationPointer
        result, node = [], self
        until node.in.empty?
          result << node
          node = node.parent
        end
        result
      end
    end

    def self.from_path(grammar, path)
      path.each_with_object(SimulatedParseContext.new(grammar)) do |sym, context|
        context.consume!(sym)
      end
    end

    def initialize(grammar)
      super()
      self.start = Node.new(nil)
      add_child(@start, grammar[0].ptrs[0])
    end

    def add_child(parent, ptr)
      # avoid cluttering the tree up with redundant nodes
      if child = parent.out.find { |node| node.ptr == ptr }
        child
      else
        super(parent, Node.new(ptr))
      end
    end

    #===========================================
    # Override some methods from Graph::Generic:
    #===========================================

    def leaves
      super.tap { |set| set.delete(@start) }
    end

    def reachable
      super.tap { |set| set.delete(@start) }
    end

    def can_reach(dests)
      super.tap { |set| set.delete(@start) }
    end

    def shortest_paths
      super.tap { |h| h.delete(@start) }.tap { |h| h.each_value { |path| path.shift }}
    end

    def node_caption(node)
      Color.without_color { (node.ptr && node.ptr.to_s) || 'ROOT' }
    end

    #======================================================
    # Taking steps forward in the simulated parsing process
    #======================================================

    # This method can be passed a terminal OR nonterminal
    # Passing a nonterminal means "a series of tokens appeared next in the
    # input which was recognized as and reduced to this nonterminal"
    # Any reduces which must be done before accepting that "series of tokens",
    # or even a single token, are done implicitly
    def consume!(sym)
      new_leaves = leaves.each_with_object([]) do |node, added|
        consume_symbol!(node, sym, added)
      end
      keep_nodes!(new_leaves)
    end

    # Shift a single terminal
    # No implicit reduce is done first
    def shift!(sym)
      raise 'Can only shift a terminal' unless sym.terminal?
      new_leaves = leaves.each_with_object([]) do |node, added|
        shift_symbol!(node, sym, added)
      end
      keep_nodes!(new_leaves)
    end

    # Commit to recognizing an already-shifted series of tokens as a certain
    # nonterminal, thus trimming the space of possible location pointers
    def reduce!(sym)
      raise 'Can only reduce a nonterminal' unless sym.nonterminal?
      if sym.nullable?
        nodes = reachable.select do |n|
          # get all leaf nodes, and any other nodes which have the nullable NT
          # as their next symbol
          !n.ptr.reduce? && (n.ptr.symbol == sym || n.out.empty?)
        end
        new_nodes = nodes.each_with_object([]) do |node, added|
          shift_symbol!(node, sym, added)
        end
      else
        new_nodes = leaves.each_with_object([]) do |node, added|
          if node.ptr.reduce? && node.parent.ptr.symbol == sym
            added << add_child(node.parent.parent, follow_reduction!(node, added))
          end
        end
      end
      raise "Can't reduce to #{sym} from current state" if new_nodes.empty?
      keep_nodes!(new_nodes)
    end

    # Trim the space of possible parse locations to those consistent with
    # `sym` being the next token in the input
    def lookahead!(sym)
      raise 'Lookahead must be a terminal' unless sym.terminal?
      new_leaves = leaves.select { |node| lookahead_valid?(node, sym) }
      keep_nodes!(new_leaves)
    end

    # what (sample) sequence of terminals/NTs could lead to a successful parse
    # from here?
    def path_to_success
      paths = shortest_paths do |_, node|
        # this cost function helps find the path to a successful parse which
        # can be described most succinctly
        node.ptr.rule.symbols.size - node.ptr.index + 1
      end
      path = paths.select { |node, _| node.out.empty? }
                  .map { |_, p| p }.min_by(&:size)

      throw :dead_end if path.nil?
      return [path[0].ptr.symbol] if path.one?

      # don't show the synthesized rule which reduces to the 'dummy' symbol
      # we need to reduce from the lowest level rule on up, so the order
      # also has to be reversed
      # all rules except for the first start with the NT which the previous
      # rule had just reduced; don't show that (it's redundant)
      path.drop(1).reverse.each_with_index.flat_map do |node, i|
        ptr = node.ptr
        ptr = ptr.next unless i == 0
        ptr.rule.symbols[ptr.index..-1] << "(reduce to #{ptr.rule.target})"
      end
    end

    def to_s
      active_ptrs = reachable.map(&:ptr)
      active_ptrs.uniq.sort_by(&:ident).map(&:to_s).join("\n")
    end

    def inspect
      return "parse context: nothing possible" if @start.nil?
      result = "parse context:\n"
      indent, stack, nodes = 0, [], @start.out.sort_by { |n| n.ptr.ident }

      until nodes.nil?
        while node = nodes.shift
          result << (' ' * indent) << node.ptr.to_s << "\n"
          stack.push(nodes)
          indent += 2
          nodes = node.out.sort_by { |n| n.ptr.ident }
        end
        nodes = stack.pop
        indent -= 2
      end

      result.chomp
    end

    private

    def keep_nodes!(nodes)
      keep = can_reach(nodes) + reachable_from(nodes) + [@start]
      @nodes.each { |node| remove_node(node) unless keep.include?(node) }
      self
    end

    # `added` is a collecting parameter for new nodes which were able to
    # 'consume' the input symbol
    def consume_symbol!(node, sym, added, dont_expand = [])
      ptr = node.ptr

      while true
        if ptr.reduce?
          ptr  = follow_reduction!(node, added)
          node = node.parent
        else
          if ptr.symbol == sym
            added << add_child(node.parent, ptr.next)
          end

          # Lazily expand child (and grandchild, etc) nodes, only expanding
          # those where we can actually shift the consumed symbol
          if ptr.symbol.first_set.include?(sym) && !dont_expand.include?(ptr)
            dont_expand.push(ptr) # avoid infinite recursion on L-recursive rules
            ptr.symbol.heads.each do |p|
              next if p.reduce?
              consume_symbol!(add_child(node, p), sym, added, dont_expand)
            end
            dont_expand.pop
          end

          ptr.symbol.nullable? ? ptr = ptr.next : return
        end
      end
    end

    # Like consume_symbol!, but don't traverse past a reduction
    def shift_symbol!(node, sym, added, dont_expand = [])
      ptr = node.ptr

      while true
        return if ptr.reduce?

        if ptr.symbol == sym
          added << add_child(node.parent, ptr.next)
        end

        if ptr.symbol.first_set.include?(sym) && !dont_expand.include?(ptr)
          dont_expand.push(ptr) # avoid infinite recursion on L-recursive rules
          ptr.symbol.heads.each do |p|
            next if p.reduce?
            shift_symbol!(add_child(node, p), sym, added, dont_expand)
          end
          dont_expand.pop
        end

        ptr.symbol.nullable? ? ptr = ptr.next : return
      end
    end

    def follow_reduction!(node, added)
      node = node.parent
      ptr  = node.ptr

      # If the reduced symbol is left-recursive, besides moving past it in
      # the parent node, also move past it in each derivation rule which
      # has it in head position
      ptr.symbol.heads.each do |head|
        if !head.reduce? && head.symbol.first_set.include?(ptr.symbol)
          consume_symbol!(add_child(node, head), ptr.symbol, added)
        end
      end

      node.ptr.next
    end

    def lookahead_valid?(node, sym)
      ptr = node.ptr

      while true
        if ptr.reduce?
          node = node.parent # go up a level
          ptr  = node.ptr.next
        elsif ptr.symbol.terminal?
          return ptr.symbol == sym
        elsif ptr.symbol.first_set.include?(sym)
          return true
        elsif ptr.symbol.nullable?
          ptr = ptr.next
        else
          return false
        end
      end
    end
  end
end