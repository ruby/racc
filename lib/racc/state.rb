# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".

require 'racc/statetransitiontable'
require 'racc/exception'
require 'forwardable'
require 'set'

module Racc

  # A table of LALR states.
  class States
    include Enumerable

    def initialize(grammar, debug_flags = DebugFlags.new)
      @grammar = grammar
      @symboltable = grammar.symboltable
      @d_state = debug_flags.state
      @d_la    = debug_flags.la
      @d_prec  = debug_flags.prec
      @states = []
      @statecache = {}
      @actions = ActionTable.new(@grammar, self)
      @nfa_computed = false
      @dfa_computed = false
      @gotos = []
    end

    attr_reader :grammar
    attr_reader :actions

    def size
      @states.size
    end

    def inspect
      '#<state table>'
    end

    alias to_s inspect

    extend Forwardable

    def_delegator "@states",  :each
    def_delegator "@actions", :shift_n
    def_delegator "@actions", :reduce_n

    def should_report_srconflict?
      sr_conflicts.any? && (sr_conflicts.size != @grammar.n_expected_srconflicts)
    end

    def sr_conflicts
      flat_map { |state| state.sr_conflicts.values }
    end

    def rr_conflicts
      flat_map { |state| state.rr_conflicts.values }
    end

    def state_transition_table
      @state_transition_table ||= StateTransitionTable.generate(compute_dfa)
    end

    #
    # NFA (Non-deterministic Finite Automaton) Computation
    #

    public

    def compute_nfa
      return self if @nfa_computed

      # add state 0
      core_to_state(Set[@grammar[0].ptrs[0]])
      # generate LALR states
      @states.each { |state| generate_states(state) }
      @actions.init

      @nfa_computed = true
      self
    end

    private

    def generate_states(state)
      puts "dstate: #{state}" if @d_state

      # build table of what the 'core' of the following state will be, if the
      # next token appearing in the input was 'sym'
      table = Hash.new { |h,k| h[k] = Set.new }
      state.closure.each do |ptr|
        if sym = ptr.symbol
          table[sym].add(ptr.next)
        end
      end

      table.each do |sym, core|
        puts "dstate: sym=#{sym} ncore=#{core}" if @d_state

        dest = core_to_state(core)
        goto = Goto.new(sym.nonterminal? && @gotos.size, sym, state, dest)
        @gotos << goto if sym.nonterminal?
        state.gotos[sym] = goto
        puts "dstate: #{state.ident} --#{sym}--> #{dest.ident}" if @d_state

        # check infinite recursion
        if state.ident == dest.ident and state.closure.size == 1
          raise CompileError,
              sprintf("Infinite recursion: state %d, with rule %d",
                      state.ident, state.ptrs[0].rule.ident)
        end
      end
    end

    def core_to_state(core)
      # a 'core' is a set of LocationPointers, indicating all the possible
      # positions within the RHS of a rule where we could be right now
      # convert core to a State object; if state does not exist, create it

      unless dest = @statecache[core]
        # not registered yet
        dest = State.new(@states.size, core)
        @states << dest
        @statecache[core] = dest

        puts "core_to_state: create state ID #{dest.ident}" if @d_state
      else
        if @d_state
          puts "core_to_state: dest is cached ID #{dest.ident}"
          puts "core_to_state: dest core #{dest.core.join(' ')}"
        end
      end

      dest
    end

    # DFA (Deterministic Finite Automaton) Generation

    public

    def compute_dfa
      return self if @dfa_computed
      compute_nfa
      compute_lookahead

      @states.each do |state|
        resolve(state)
      end
      set_accept
      @states.each do |state|
        pack(state)
      end

      @dfa_computed = true
      self
    end

    private

    def compute_lookahead
      # lookahead algorithm ver.3 -- from bison 1.26
      gotos = @gotos

      # build a bitmap which shows which terminals could possibly appear next
      # after each reduction in the grammar
      # (we will use this information to decide which reduction to perform if
      # two of them are possible, or whether to do a shift or a reduce if both
      # are possible)
      # (if both reductions A and B are possible, but we see that the next token
      # can only validly appear after reduction A and not B, then we will choose
      # to perform reduction A)
      following_terminals = create_bitmap(gotos.size)
      look_past = DirectedGraph.new(gotos.size)
      gotos.each do |goto|
        goto.to_state.gotos.each do |tok, next_goto|
          if tok.terminal?
            # set bit for terminal which could be shifted after this reduction
            following_terminals[goto.ident] |= (1 << tok.ident)
          elsif tok.nullable?
            # if a nullable NT could come next, then we have to look past it
            # to see which terminals could appear next
            look_past.add_arrow(goto.ident, next_goto.ident)
          end
        end
      end
      # traverse graph with arrows connecting reductions which could occur
      # directly after another without shifting any terminal first (because the
      # reduced nonterminal is null)
      walk_graph(following_terminals, look_past)

      # there is another case we have to consider to get the full set of tokens
      # which can validly appear after each reduction...
      # what if we do 2 reductions in a row? or 3, 4, 5...?
      # if terminal T1 can appear after nonterminal A, and we can reduce to A
      # immediately after reducing to B, that means terminal T1 could also
      # appear after B

      # but that's not all! think about this:
      # what if we have a rule like "A = BC", and we know terminal T1 can appear
      # after A, *and C is nullable*?
      # that means T1 can also appear after B, not just after C

      includes = DirectedGraph.new(gotos.size)
      # look at the state transition triggered by each reduction in the grammar
      # (at each place in the state graph where that reduction can occur)
      gotos.each do |goto|
        # look at RHS of each rule which could have lead to this reduction
        goto.symbol.heads.each do |ptr|
          # what sequence of state transitions would we have made to reach
          # this reduction, if this is the rule that was used?
          path(goto.from_state, ptr.rule).reverse_each do |preceding_goto|
            break if     preceding_goto.symbol.terminal?
            includes.add_arrow(preceding_goto.ident, goto.ident)
            break unless preceding_goto.symbol.nullable?
          end
        end
      end

      walk_graph(following_terminals, includes)

      # Now we know which terminals can follow each reduction
      # But this lookahead information is only needed when there would otherwise
      # be a S/R or R/R conflict

      # So, find all the states leading to a possible reduce, where there is a
      # S/R or R/R conflict, and copy the lookahead set for each reduce to the
      # preceding state which has the conflict

      gotos.each do |goto|
        goto.symbol.heads.each do |ptr|
          path = path(goto.from_state, ptr.rule)
          prev_state = (path.last && path.last.to_state) || goto.from_state
          if prev_state.conflict?
            ritem = prev_state.ritems.find { |item| item.rule == ptr.rule }
            ritem.la |= following_terminals[goto.ident]
          end
        end
      end
    end

    def create_bitmap(size)
      Array.new(size, 0) # use Integer as bitmap
    end

    # Sequence of state transitions which would be taken when starting
    # from 'state', then following the RHS of 'rule' right to the end
    def path(state, rule)
      rule.symbols.each_with_object([]) do |tok, path|
        goto = state.gotos[tok]
        path << goto
        state = goto.to_state
      end
    end

    # traverse a directed graph
    # each entry in 'bitmap' corresponds to a graph node
    # after the traversal, the bitmap for each node will be the union of its
    # original value, and ALL the values for all the nodes which are reachable
    # from it
    def walk_graph(bitmap, graph)
      index    = Array.new(graph.size, nil)
      traversed = Set.new

      graph.nodes do |node|
        next if traversed.include?(node)
        traverse(node, traversed, index, [], bitmap, graph)
      end
    end

    def traverse(node, traversed, index, stack, bitmap, graph)
      traversed.add(node)
      stack.push(node)
      index[node] = stack_depth = stack.size

      graph.arrows(node) do |next_node|
        unless index[next_node]
          traverse(next_node, traversed, index, stack, bitmap, graph)
        end

        if index[node] > index[next_node]
          # there is a cycle in the graph
          # we already passed through 'next_node' to reach here
          index[node] = index[next_node]
        end

        bitmap[node] |= bitmap[next_node]
      end

      if index[node] == stack_depth
        while true
          next_node = stack.pop
          index[next_node] = graph.size + 2
          break if node == next_node

          bitmap[next_node] |= bitmap[node]
        end
      end
    end

    #
    # resolve
    #

    def resolve(state)
      if state.conflict?
        resolve_rr(state, state.ritems)
        resolve_sr(state, state.stokens)
      elsif state.rrules.empty?
        # shift
        state.stokens.each do |t|
          state.action[t] = @actions.shift(state.gotos[t].to_state)
        end
      else
        # only reduce is possible; we won't even bother looking at the next
        # token in this state
        state.defact = @actions.reduce(state.rrules[0])
      end
    end

    def resolve_rr(state, r)
      r.each do |item|
        item.each_la(@symboltable) do |t|
          act = state.action[t]
          if act
            # Cannot resolve R/R conflict (on t).
            # Reduce with upper rule as default.
            state.rr_conflict!(act.rule, item.rule, t)
          else
            # No conflict.
            state.action[t] = @actions.reduce(item.rule)
          end
        end
      end
    end

    def resolve_sr(state, stokens)
      stokens.each do |stok|
        goto = state.gotos[stok]
        act = state.action[stok]

        unless act
          # no conflict
          state.action[stok] = @actions.shift(goto.to_state)
        else
          # conflict
          rtok = act.rule.precedence
          case do_resolve_sr(stok, rtok)
          when :Reduce
            # action is already set

          when :Shift
            # overwrite
            state.action[stok] = @actions.shift(goto.to_state)

          when :Error
            state.action[stok] = @actions.error

          when :CantResolve
            # shift as default
            state.action[stok] = @actions.shift(goto.to_state)
            state.sr_conflict!(stok, act.rule)
          end
        end
      end
    end

    ASSOC = {
      :Left     => :Reduce,
      :Right    => :Shift,
      :Nonassoc => :Error
    }

    def do_resolve_sr(stok, rtok)
      puts "resolve_sr: s/r conflict: rtok=#{rtok}, stok=#{stok}" if @d_prec

      unless rtok and rtok.precedence
        puts "resolve_sr: no prec for #{rtok}(R)" if @d_prec
        return :CantResolve
      end
      rprec = rtok.precedence

      unless stok and stok.precedence
        puts "resolve_sr: no prec for #{stok}(S)" if @d_prec
        return :CantResolve
      end
      sprec = stok.precedence

      ret = if rprec == sprec
              ASSOC[rtok.assoc] or
                  raise "racc: fatal: #{rtok}.assoc is not Left/Right/Nonassoc"
            else
              (rprec > sprec) ? (:Reduce) : (:Shift)
            end

      puts "resolve_sr: resolved as #{ret.id2name}" if @d_prec
      ret
    end

    #
    # complete
    #

    def set_accept
      anch = @symboltable.anchor
      init_state = @states[0].gotos[@grammar.start].to_state
      targ_state = init_state.action[anch].goto_state
      acc_state  = targ_state.action[anch].goto_state

      acc_state.action.clear
      acc_state.defact = @actions.accept
    end

    def pack(state)
      ### find most frequently used reduce rule
      act = state.action
      arr = Array.new(@grammar.size, 0)
      act.each do |t, a|
        arr[a.rule_id] += 1  if a.kind_of?(Reduce)
      end
      i = arr.max
      s = (i > 0) ? arr.index(i) : nil

      ### set & delete default action
      if s
        r = @actions.reduce(s)
        if not state.defact or state.defact == r
          act.delete_if {|t, a| a == r }
          state.defact = r
        end
      else
        state.defact ||= @actions.error
      end
    end
  end

  class DirectedGraph < Array
    def initialize(size)
      super(size) { [] }
    end

    def add_arrow(from, to)
      self[from] << to
    end

    alias nodes each_index

    def arrows(from, &block)
      self[from].each(&block)
    end
  end

  # A LALR state.
  class State
    def initialize(ident, core)
      @ident = ident # ID number used to provide a canonical ordering
      @core = core # LocationPointers to all the possible positions within the
                   # RHS of a rule where we could be when in this state
      @gotos = {}
      @ritems = nil
      @action = {}
      @defact = nil
      @rr_conflicts = {}
      @sr_conflicts = {}
    end

    attr_reader :ident
    attr_reader :core
    attr_reader :gotos

    attr_reader :action
    attr_accessor :defact   # default action

    attr_reader :rr_conflicts
    attr_reader :sr_conflicts

    def inspect
      "<state #{@ident}>"
    end

    alias to_s inspect

    def closure
      # Say we know that we are at "A = B . C" right now; in other words,
      # we know that we are parsing an "A", we have already finished the "B",
      # and the "C" should be coming next
      # If "C" is a non-terminal, then that means the RHS of one of the rules
      # for C should come next (but we don't know which one)
      # So we could possibly be beginning ANY of the rules for C here
      # But if one of the rules for C itself starts with non-terminal "D"...
      # well, to find all the possible positions where we could be in each
      # rule, we have to recurse down into all the rules for D (and so on)
      # This recursion has already been done and the result cached in Sym#expand
      @closure ||= @core.each_with_object(Set.new) do |ptr, set|
        set.add(ptr)
        if sym = ptr.symbol and sym.nonterminal?
          set.merge(sym.expand)
        end
      end.sort_by(&:ident)
    end

    def stokens
      @stokens ||= closure.map(&:symbol).compact.select(&:terminal?).uniq.sort_by(&:ident)
    end

    def rrules
      @rrules ||= closure.select(&:reduce?).map(&:rule)
    end

    # would there be a S/R or R/R conflict IF lookahead was not used?
    def conflict?
      @conflict ||= begin
        (rrules.size > 1) ||
        (stokens.any? { |tok| tok.ident == 1 }) || # $error symbol
        (stokens.any? && rrules.any?)
      end
    end

    # rules for which we need a lookahead set (to disambiguate which of them we
    # should apply next)
    def ritems
      @ritems ||= conflict? ? rrules.map { |rule| Item.new(rule) } : []
    end

    def rr_conflict!(high, low, ctok)
      @rr_conflicts[ctok] = RRConflict.new(@ident, high, low, ctok)
    end

    def sr_conflict!(shift, reduce)
      @sr_conflicts[shift] = SRConflict.new(@ident, shift, reduce)
    end
  end

  # Represents a transition between states in the grammar
  # Descriptions of the LR algorithm only talk about doing a "goto" after
  # reducing, but this class can also represent a state transition which occurs
  # after shifting
  # If 'symbol' is a terminal, then ident will be nil (there is no global
  # ordering of such Gotos).
  #
  class Goto < Struct.new(:ident, :symbol, :from_state, :to_state)
    def inspect
      "(#{from_state.ident}-#{symbol}->#{to_state.ident})"
    end
  end

  # LALR item. A rule and its lookahead tokens.
  class Item
    def initialize(rule)
      @rule = rule
      @la   = 0 # bitmap
    end

    attr_reader :rule
    attr_accessor :la

    def each_la(tbl)
      la = @la
      0.upto(la.size - 1) do |i|
        (0..7).each do |ii|
          if la[idx = i * 8 + ii] == 1
            yield tbl[idx]
          end
        end
      end
    end
  end

  # The table of LALR actions. Actions are either
  # Shift, Reduce, Accept, or Error.
  class ActionTable
    def initialize(grammar, statetable)
      @grammar = grammar
      @statetable = statetable

      @reduce = []
      @shift = []
      @accept = Accept.new
      @error = Error.new
    end

    def init
      @reduce = @grammar.map { |rule| Reduce.new(rule) }
      @shift = @statetable.map { |state| Shift.new(state) }
    end

    def reduce_n
      @reduce.size
    end

    def reduce(i)
      case i
      when Rule    then i = i.ident
      when Integer then ;
      else
        raise "racc: fatal: wrong class #{i.class} for reduce"
      end

      @reduce[i] or raise "racc: fatal: reduce action #{i.inspect} not exist"
    end

    def shift_n
      @shift.size
    end

    def shift(i)
      case i
      when State   then i = i.ident
      when Integer then ;
      else
        raise "racc: fatal: wrong class #{i.class} for shift"
      end

      @shift[i] or raise "racc: fatal: shift action #{i} does not exist"
    end

    attr_reader :accept
    attr_reader :error
  end

  class Shift < Struct.new(:goto_state)
    def goto_id
      goto_state.ident
    end

    def inspect
      "<shift #{goto_state.ident}>"
    end
  end

  class Reduce < Struct.new(:rule)
    def rule_id
      rule.ident
    end

    def inspect
      "<reduce #{rule.ident}>"
    end
  end

  class Accept
    def inspect
      "<accept>"
    end
  end

  class Error
    def inspect
      "<error>"
    end
  end

  class SRConflict < Struct.new(:stateid, :shift, :reduce)
    def to_s
      sprintf('state %d: S/R conflict rule %d reduce and shift %s',
              @stateid, reduce.ruleid, @shift.to_s)
    end
  end

  class RRConflict < Struct.new(:stateid, :high_prec, :low_prec, :token)
    def to_s
      sprintf('state %d: R/R conflict with rule %d and %d on %s',
              stateid, high_prec.ident, low_prec.ident, token.to_s)
    end
  end
end
