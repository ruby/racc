# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".

require 'racc/state_transition_table'
require 'racc/exception'
require 'racc/util'
require 'racc/directed_graph'
require 'racc/simulated_parse_context'

require 'set'

module Racc
  class States
    include Enumerable

    def initialize(grammar)
      @grammar = grammar
      @states  = []
      @gotos   = [] # all state transitions performed when reducing
                    # Goto is also used for state transitions when shifting,
                    # but those objects don't go in this array

      generate_states
      compute_lookahead

      @states.each { |state| resolve(state) }
      set_accept
      @states.each { |state| pack(state) }
    end

    attr_reader :grammar
    attr_reader :actions

    def each(&block)
      @states.each(&block)
    end

    def size
      @states.size
    end

    def inspect
      '#<state table>'
    end

    alias to_s inspect

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
      @state_transition_table ||= StateTransitionTable.generate(self)
    end

    private

    def generate_states
      # create start state
      start = State.new(0, Set[@grammar[0].ptrs[0]], [])

      @states << start
      states = {start.core => start}
      worklist = [start]

      until worklist.empty?
        state = worklist.shift

        # build table of what the 'core' of the following state will be, if the
        # next token appearing in the input was 'sym'
        #
        # a 'core' is a set of LocationPointers, indicating all the possible
        # positions within the RHS of a rule where we could be right now
        # convert core to a State object; if state does not exist, create it

        table = Hash.new { |h,k| h[k] = Set.new }
        state.closure.each do |ptr|
          table[ptr.symbol].add(ptr.next) unless ptr.reduce?
        end

        table.each do |sym, core|
          # each possible 'core' corresponds to one LALR state

          unless dest = states[core]
            # not registered yet
            path = state.path.dup << sym
            dest = State.new(@states.size, core, path.freeze)
            @states << dest
            worklist << dest
            states[core] = dest
          end

          goto = Goto.new(sym.nonterminal? && @gotos.size, sym, state, dest)
          @gotos << goto if sym.nonterminal?
          state.gotos[sym] = goto

          if state.ident == dest.ident and state.closure.size == 1
            rule = state.ptrs[0].rule
            raise CompileError, "Infinite recursion in rule: #{rule}"
          end
        end
      end
    end

    def compute_lookahead
      # lookahead algorithm ver.3 -- from bison 1.26

      # build a bitmap which shows which terminals could possibly appear next
      # after each reduction in the grammar
      # (we will use this information to decide which reduction to perform if
      # two of them are possible, or whether to do a shift or a reduce if both
      # are possible)
      # (if both reductions A and B are possible, but we see that the next token
      # can only validly appear after reduction A and not B, then we will choose
      # to perform reduction A)
      following_terminals = create_bitmap(@gotos.size)
      look_past = Graph::Finite.new(@gotos.size)
      @gotos.each do |goto|
        goto.to_state.gotos.each do |tok, next_goto|
          if tok.terminal?
            # set bit for terminal which could be shifted after this reduction
            following_terminals[goto.ident] |= (1 << tok.ident)
          elsif tok.nullable?
            # if a nullable NT could come next, then we have to look past it
            # to see which terminals could appear next
            look_past.add_child(goto.ident, next_goto.ident)
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

      includes = Graph::Finite.new(@gotos.size)
      # look at the state transition triggered by each reduction in the grammar
      # (at each place in the state graph where that reduction can occur)
      @gotos.each do |goto|
        # look at RHS of each rule which could have lead to this reduction
        goto.symbol.heads.each do |ptr|
          # what sequence of state transitions would we have made to reach
          # this reduction, if this is the rule that was used?
          path(goto.from_state, ptr.rule).reverse_each do |preceding_goto|
            break if     preceding_goto.symbol.terminal?
            includes.add_child(preceding_goto.ident, goto.ident)
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

      @gotos.each do |goto|
        goto.symbol.heads.each do |ptr|
          path = path(goto.from_state, ptr.rule)
          prev_state = (path.last && path.last.to_state) || goto.from_state
          if prev_state.conflict?
            ritem = prev_state.ritems.find { |item| item.rule == ptr.rule }
            ritem.lookahead |= following_terminals[goto.ident]
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

      graph.children(node) do |next_node|
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

    def resolve(state)
      if state.conflict?
        resolve_rr(state, state.ritems)
        resolve_sr(state, state.stokens)
      elsif state.rrules.empty?
        # shift
        state.stokens.each do |t|
          state.action[t] = Shift.new(state.gotos[t].to_state)
        end
      else
        # only reduce is possible; we won't even bother looking at the next
        # token in this state
        state.defact = Reduce.new(state.rrules[0])
      end
    end

    def resolve_rr(state, ritems)
      rrules = Hash.new { |h,k| h[k] = [] }

      ritems.each do |item|
        item.each_lookahead_token(@grammar.symbols) do |sym|
          rrules[sym] << item.rule
        end
      end

      rrules.each do |sym, rules|
        # If there is a conflict, reduce with the rule which appeared
        # first in the source
        state.action[sym] = Reduce.new(rules[0])
        if rules.size > 1
          state.rr_conflict!(sym, rules)
          rules.drop(1).each do |rule|
            rule.overridden_by[sym] << rules[0]
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
          state.action[stok] = Shift.new(goto.to_state)
        else
          # conflict
          rtok = act.rule.precedence
          case do_resolve_sr(stok, rtok, act.rule)
          when :Reduce
            # action is already set

          when :Shift
            # overwrite
            act.rule.overridden_by[stok].merge(state.srules[stok].map(&:rule))
            state.action[stok] = Shift.new(goto.to_state)

          when :Error
            state.action[stok] = Error.new

          when :CantResolve
            # shift as default
            srules = state.srules[stok]
            act.rule.overridden_by[stok].merge(srules.map(&:rule))
            state.action[stok] = Shift.new(goto.to_state)
            state.sr_conflict!(stok, srules, act.rule)
          end
        end
      end
    end

    ASSOC = {
      :Left     => :Reduce,
      :Right    => :Shift,
      :Nonassoc => :Error
    }

    def do_resolve_sr(stok, rtok, rrule)
      return :CantResolve unless rtok && (rprec = rtok.precedence)
      return :CantResolve unless stok && (sprec = stok.precedence)

      rrule.explicit_precedence_used!

      if rprec == sprec
        ASSOC[rtok.assoc] ||
        (raise "racc: fatal: #{rtok}.assoc is not Left/Right/Nonassoc")
      else
        (rprec > sprec) ? :Reduce : :Shift
      end
    end

    def set_accept
      anch = @grammar.anchor
      init_state = @states[0].gotos[@grammar.start].to_state
      targ_state = init_state.action[anch].goto_state
      acc_state  = targ_state.action[anch].goto_state

      acc_state.action.clear
      acc_state.defact = Accept.new
    end

    def pack(state)
      # find most frequently used reduce rule, and make it the default action
      state.defact ||= begin
        freq = Hash.new(0)
        state.action.each do |tok, act|
          freq[act.rule] += 1 if act.is_a?(Reduce)
        end

        if freq.empty?
          Error.new
        else
          most_common = freq.keys.max_by { |rule| freq[rule] }
          reduce = Reduce.new(most_common)
          state.action.delete_if { |tok, act| act == reduce }
          reduce
        end
      end
    end

    public

    def useless_rules
      used_rules = Set.new
      @states.each do |state|
        state.action.each do |tok, act|
          used_rules << act.rule if act.is_a?(Reduce)
        end
        used_rules << state.defact.rule if state.defact.is_a?(Reduce)
      end
      Set.new(@grammar) - used_rules
    end

    def warnings(warnings, verbose = false)
      useless_rules.each do |rule|
        next unless warnings.for_rule(rule).empty? &&
                    !rule.overridden_by.empty?
        warnings.add_for_rule(rule, Warning::RuleAlwaysOverridden.new(rule))
      end

      if should_report_srconflict?
        sr_conflicts.each do |sr|
          warnings.add_for_state(sr.state,
            Warning::SRConflict.new(sr, @grammar, verbose))
        end
      end

      rr_conflicts.each do |rr|
        warnings.add_for_state(rr.state,
          Warning::RRConflict.new(rr, @grammar, verbose))
      end

      warnings
    end
  end

  class State
    def initialize(ident, core, path)
      @ident = ident # ID number used to provide a canonical ordering
      @core  = core  # LocationPointers to all the possible positions within the
                     # RHS of a rule where we could be when in this state
      @path  = path  # sample sequence of terms/nonterms which would lead here
                     # (for diagnostics)

      @gotos  = {}   # Sym -> Goto describing state transition if we encounter
                     # that Sym next
      @action = {}   # Sym -> Shift/Reduce/Accept/Error describing what we will
                     # do if we encounter that Sym next
      @defact = nil  # if action table has no entry for a certain lookahead
                     # token, perform this action instead
                     # (if action table is empty, just perform this action
                     # without even checking the lookahead token)
      @rr_conflicts = {}
      @sr_conflicts = {}
    end

    attr_reader :ident
    attr_reader :core
    attr_reader :path
    attr_reader :gotos
    attr_reader :action
    attr_accessor :defact # default action
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
      @stokens ||= closure.reject(&:reduce?).map(&:symbol).select(&:terminal?)
                     .uniq.sort_by(&:ident)
    end

    # {Sym -> LocationPointers within rules which direct us to shift that Sym}
    def srules
      @srules ||= begin
        closure.each_with_object(Hash.new { |h,k| h[k] = [] }) do |ptr, table|
          next if ptr.reduce? || ptr.symbol.nonterminal?
          table[ptr.symbol] << ptr
        end
      end
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

    def rr_conflict!(sym, rules)
      @rr_conflicts[sym] = RRConflict.new(self, sym, rules)
    end

    def sr_conflict!(token, srule, rrule)
      @sr_conflicts[token] = SRConflict.new(self, token, srule, rrule)
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

  # LALR item: a rule and its lookahead tokens
  class Item
    def initialize(rule)
      @rule = rule
      @lookahead = 0 # bitmap of terminal ID numbers (Sym#ident)
    end

    attr_reader :rule
    attr_accessor :lookahead

    def each_lookahead_token(tbl)
      0.upto((@lookahead.size * 8) - 1) do |idx|
        yield tbl[idx] if @lookahead[idx] == 1
      end
    end
  end

  class Shift < Struct.new(:goto_state)
    def inspect
      "<shift #{goto_state.ident}>"
    end
  end

  class Reduce < Struct.new(:rule)
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

  class SRConflict < Struct.new(:state, :symbol, :srules, :rrule)
    def to_s
      "state #{state.ident}: S/R conflict on #{symbol} between shift rules " \
      "#{srules} and reduce rule #{rrule}"
    end
  end

  class RRConflict < Struct.new(:state, :symbol, :rules)
    def to_s
      "state #{state.ident}: R/R conflict on #{symbol} between reduce rules " \
      "#{rrules}"
    end
  end
end
