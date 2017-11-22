# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of LGPL, see the file "COPYING".

require 'racc/parser'

module Racc

  TRANSITION_TABLE_ATTRS =
    [:action_table,   :action_check,    :action_default, :action_pointer,
     :goto_table,     :goto_check,      :goto_default,   :goto_pointer,
     :token_table,    :reduce_table,    :reduce_n,       :shift_n,
     :nt_base,        :token_to_s_table,
     :use_result_var, :debug_parser]

  class StateTransitionTable < Struct.new(*TRANSITION_TABLE_ATTRS)
    def StateTransitionTable.generate(states)
      StateTransitionTableGenerator.new(states).generate
    end

    def initialize(states)
      super()
      @states = states
      @grammar = states.grammar
      self.use_result_var = true
      self.debug_parser = true
    end

    attr_reader :states
    attr_reader :grammar

    def parser_class
      ParserClassGenerator.new(@states).generate
    end

    def token_value_table
      Hash[token_table.map { |sym, i| [sym.value, i]}]
    end
  end

  class StateTransitionTableGenerator
    def initialize(states)
      @states = states
      @grammar = states.grammar
    end

    def generate
      t = StateTransitionTable.new(@states)
      gen_action_tables t, @states
      gen_goto_tables t, @grammar
      t.token_table = token_table(@grammar)
      t.reduce_table = reduce_table(@grammar)
      t.reduce_n = @grammar.size
      t.shift_n = @states.size
      t.nt_base = @grammar.nonterminal_base
      t.token_to_s_table = @grammar.symbols.map {|sym| sym.to_s }
      t
    end

    def reduce_table(grammar)
      # reduce_table has 3 items for each grammar rule:
      # [number of items to pop off stack when reducing,
      #  ID number of non-terminal to push on stack after reducing,
      #  method to call to perform the rule's action]
      t = [0, 0, :racc_error]
      grammar.each_with_index do |rule, idx|
        next if idx == 0
        t.push rule.size
        t.push rule.target.ident
        t.push(rule.action.empty? ? :_reduce_none : "_reduce_#{idx}".to_sym)
      end
      t
    end

    def token_table(grammar)
      Hash[grammar.terminals.map { |t| [t, t.ident]}]
    end

    # The action and goto tables use a clever trick for compression
    # Each state should have its own action table (one per lookahead token)
    # Each nonterminal which we can reduce to also has its own goto table
    # (with one entry per state which we can perform the reduction from)
    # But those tables are very sparse (most entries are nil)
    #
    # So, to save space, we OVERLAY all the action tables into one big array
    # And same with the goto tables
    # We must choose an offset for each state, so its populated entries don't
    # collide with the populated entries of any other state
    # The chosen offsets go in the 'action_pointer' and 'goto_pointer' arrays
    # At runtime, we will retrieve the offset for the current state, add the
    # token number of the lookahead token, and index into the action/goto table
    #
    # BUT, what if the lookahead token is one which is illegal in this state?
    # OR, what if it's legal, but its entry is the default entry (which does
    # not explicitly appear in the main action/goto tables)?
    # We could blindly hit an entry which belongs to a different state, and go
    # off into some random sequence of states
    # To prevent this, there are 'check' arrays with the state numbers which
    # each action/goto entry belong to
    # So before we retrieve an action/goto and use it, we see whether the
    # corresponding 'check' number is the current state number

    def gen_action_tables(t, states)
      t.action_default = states.map { |s| act2actid(s.defact) }
      t.action_table   = []
      t.action_check   = []
      t.action_pointer = []

      entries = []
      states.each do |state|
        if state.action.empty?
          # there is ONLY one default action in this state
          # when the parser sees that the 'action pointer' (or offset) for this
          # state is nil, it will just execute the default action
          t.action_pointer << nil
        else
          # build the action table for this state
          actions = []
          state.action.each do |tok, act|
            actions[tok.ident] = act2actid(act)
          end
          # then store data which will be used when we overlay all the per-state
          # action tables into one big action table
          add_entry(entries, actions, state.ident, t.action_pointer)
        end
      end

      set_table(entries, t.action_table, t.action_check, t.action_pointer)
    end

    def gen_goto_tables(t, grammar)
      t.goto_table   = []
      t.goto_check   = []
      t.goto_pointer = []
      t.goto_default = []
      entries = []

      # for each nonterminal, choose most common destination state after
      # reduce as the default destination state
      grammar.nonterminals.each do |tok|
        freq = Hash.new(0)
        @states.each do |state|
          if goto = state.gotos[tok]
            freq[goto.to_state.ident] += 1
          end
        end

        most_common = freq.keys.max_by { |k| freq[k] }
        if most_common && freq[most_common] > 1
          t.goto_default << most_common
        else
          t.goto_default << nil
        end
      end

      # now build goto table for each nonterminal, and record data which will
      # be used when overlaying all the individual goto tables into the main
      # goto table
      grammar.nonterminals.zip(t.goto_default).each do |tok, default|
        array = @states.map do |state|
          if goto = state.gotos[tok]
            to_state = goto.to_state.ident
            to_state unless to_state == default
          end
        end

        if array.compact.empty?
          # there is ONLY one destination state which we can transition to after
          # reducing down to this nonterminal
          t.goto_pointer << nil
        else
          array.pop until array.last || array.empty?
          add_entry(entries, array, (tok.ident - grammar.nonterminal_base),
                    t.goto_pointer)
        end
      end

      set_table(entries, t.goto_table, t.goto_check, t.goto_pointer)
    end

    def add_entry(all, array, chkval, ptr_array)
      # array is an action/goto array for one state
      # the array indices are token numbers
      # prepare the data which will be needed when we overall ALL these arrays
      # into one big array:
      min = array.index { |item| item }
      array = array.drop(min)
      ptr_array << :just_reserving_space_and_will_be_overwritten
      all << [array, chkval, mkmapexp(array), min, ptr_array.size - 1]
    end

    n = 2 ** 16
    begin
      Regexp.compile("a{#{n}}")
      RE_DUP_MAX = n
    rescue RegexpError
      n /= 2
      retry
    end

    def mkmapexp(arr)
      map = String.new
      maxdup = RE_DUP_MAX

      arr.chunk(&:nil?).each do |is_nil, items|
        char = is_nil ? '.' : '-'
        if (offset = items.size) == 1
          map << char
        else
          while offset > maxdup
            map << "#{char}{#{maxdup}}"
            offset -= maxdup
          end
          map << "#{char}{#{offset}}" if offset > 0
        end
      end

      Regexp.compile(map, 'n')
    end

    def set_table(entries, tbl, chk, ptr)
      upper = 0
      map = '-' * 10240

      # sort long to short
      # we want a stable sort, so that the output will not be dependent on
      # the sorting algorithm used by the underlying Ruby implementation
      entries.each_with_index.map { |a, i| a.unshift(i) }
      entries.sort! do |a, b|
        # find space for the big ones first; it is more likely that the small
        # ones will "fit in the cracks"
        comp = (b[1].size <=> a[1].size)
        comp = (a[0] <=> b[0]) if comp == 0
        comp
      end

      entries.each do |_, arr, chkval, expr, min, ptri|
        if upper + arr.size > map.size
          map << '-' * (arr.size + 1024)
        end
        idx = map.index(expr)
        ptr[ptri] = idx - min
        arr.each_with_index do |item, i|
          if item
            i += idx
            tbl[i] = item
            chk[i] = chkval
            map[i] = 'o'
          end
        end
        upper = idx + arr.size
      end
    end

    def act2actid(act)
      case act
      when Shift  then act.goto_state.ident
      when Reduce then -act.rule.ident
      when Accept then @states.size
      when Error  then @grammar.size * -1
      else
        raise "racc: fatal: wrong act type #{act.class} in action table"
      end
    end
  end

  class ParserClassGenerator
    def initialize(states)
      @states = states
      @grammar = states.grammar
    end

    def generate
      table = @states.state_transition_table
      c = Class.new(::Racc::Parser)
      c.const_set :Racc_arg, [table.action_table,
                              table.action_check,
                              table.action_default,
                              table.action_pointer,
                              table.goto_table,
                              table.goto_check,
                              table.goto_default,
                              table.goto_pointer,
                              table.nt_base,
                              table.reduce_table,
                              table.token_value_table,
                              table.shift_n,
                              table.reduce_n,
                              false]
      c.const_set :Racc_token_to_s_table, table.token_to_s_table
      c.const_set :Racc_debug_parser, true
      define_actions c
      c
    end

    private

    def define_actions(c)
      c.module_eval "def _reduce_none(vals, vstack) vals[0] end"
      @grammar.each do |rule|
        if rule.action.empty?
          c.__send__(:alias_method, "_reduce_#{rule.ident}", :_reduce_none)
        else
          c.__send__(:define_method, "_racc_action_#{rule.ident}", &rule.action.proc)
          c.module_eval(<<-End, __FILE__, __LINE__ + 1)
            def _reduce_#{rule.ident}(vals, vstack)
              _racc_action_#{rule.ident}(*vals)
            end
          End
        end
      end
    end
  end
end
