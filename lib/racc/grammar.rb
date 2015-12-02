# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".

require 'racc/source'
require 'racc/exception'
require 'racc/color'
require 'racc/warning'
require 'racc/util'
require 'set'

module Racc
  class Grammar
    include Enumerable

    def initialize
      @symbols = [] # all Syms used in a grammar
      @cache   = {} # map of String/Symbol name -> Sym
      @rules = []
      @start = nil

      @n_expected_srconflicts = nil

      @prec_table = []
      @prec_table_closed = false

      @closed = false
      @states = States.new(self)

      # 'dummy' and 'anchor' are used to make sure the parser runs over ALL the
      # input tokens before concluding that the parse was successful
      # an 'anchor' token is appended to the end of the token stream, and a
      # 'dummy rule' is automatically added which looks like:
      # dummy : start anchor anchor
      # We never actually reduce to the dummy symbol; instead, we manually set
      # 'dummy : start anchor . anchor' to be an 'accept state'

      @dummy   = intern(:$start, true)
      @anchor  = intern(false, true)   # Symbol ID = 0
      @error   = intern(:error, false) # Symbol ID = 1
    end

    attr_reader :states
    attr_reader :start
    attr_reader :n_expected_srconflicts
    attr_reader :terminals
    attr_reader :nonterminals
    attr_reader :symbols
    attr_reader :dummy
    attr_reader :anchor
    attr_reader :error

    def [](x)
      @rules[x]
    end

    def each(&block)
      @rules.each(&block)
    end

    def size
      @rules.size
    end

    def to_s
      "<Racc::Grammar>"
    end

    def intern(val, dummy = false)
      if @closed
        @cache[val] || (raise "No such symbol: #{val}")
      else
        @cache[val] ||= Sym.new(val, self, dummy).tap { |sym| @symbols.push(sym) }
      end
    end

    def delete_symbol(sym)
      @symbols.delete(sym)
      @cache.delete(sym.value)
    end

    def sr_conflicts
      @states.sr_conflicts
    end

    def rr_conflicts
      @states.rr_conflicts
    end

    def nonterminal_base
      @terminals.size
    end

    def locations
      raise 'Grammar not yet closed' unless @closed
      @locations ||= @rules.flat_map(&:ptrs)
    end

    def n_expected_srconflicts=(value)
      if @n_expected_srconflicts
        raise CompileError, "'expect' seen twice"
      end
      @n_expected_srconflicts = value
    end

    def state_transition_table
      @states.state_transition_table
    end

    def parser_class
      state_transition_table.parser_class
    end

    def warnings(verbose)
      warnings = []

      useless_symbols.each do |sym|
        if sym.locate.empty?
          what = sym.terminal? ? 'terminal' : 'nonterminal'
          type = "useless_#{what}".to_sym
          warnings << Warning.new(type, "Useless #{what} #{sym} does not " \
            'appear on the right side of any rule, neither is it the start ' \
            'symbol.')
        elsif !sym.reachable.include?(@start) && sym.reachable.include?(sym)
          if sym.reachable.one?
            warnings << Warning.new(:useless_nonterminal, 'Useless ' \
              "nonterminal #{sym} only appears on the right side of its " \
              'own rules.')
          else
            warnings << Warning.new(:useless_nonterminal, 'Useless ' \
              "nonterminal #{sym} cannot be part of a valid parse tree, " \
              'since there is no sequence of reductions from it to the ' \
              'start symbol.', 'It can only reduce to: ' \
              "#{sym.reachable.map(&:to_s).join(', ')}")
          end
        elsif !productive_symbols.include?(sym)
          warnings << Warning::InfiniteLoop.new(sym)
        end
      end

      select { |r| r.explicit_precedence && !r.explicit_precedence_used? }.each do |rule|
        warnings << Warning::UselessPrecedence.new(rule)
      end

      warnings.concat(@states.warnings(verbose))
    end

    # Grammar Definition Interface

    def add(rule)
      raise ArgumentError, "rule added after Grammar closed" if @closed
      @rules.push rule
    end

    def added?(sym)
      @rules.detect {|r| r.target == sym }
    end

    def start_symbol=(s)
      raise CompileError, "start symbol set twice" if @start
      @start = s
    end

    def declare_precedence(assoc, syms)
      raise CompileError, "precedence table defined twice" if @prec_table_closed
      @prec_table.push [assoc, syms]
    end

    def end_precedence_declaration(reverse)
      @prec_table_closed = true
      return if @prec_table.empty?
      table = reverse ? @prec_table.reverse : @prec_table
      table.each_with_index do |(assoc, syms), idx|
        syms.each do |sym|
          sym.assoc = assoc
          sym.precedence = idx
        end
      end
    end

    # Computation

    def finished!
      return if @closed
      @closed = true

      # if 'start' nonterminal was not explicitly set, just take the first one
      @start ||= map(&:target).detect { |sym| !sym.dummy? }
      fail CompileError, 'no rules in input' if @rules.empty?
      add_start_rule

      @rules.freeze
      @symbols.each do |sym|
        sym.heads.freeze
        sym.locate.freeze
      end
      @cache.freeze

      fix_ident
      check_terminals
      check_rules
    end

    # A 'useless' Sym is one which can never be part of a valid parse
    # tree, because there is no sequence of rules by which it
    # could eventually reduce down to the 'start' node
    def useless_symbols
      raise 'Grammar not yet closed' unless @closed
      @useless_symbols ||= begin
        @symbols.select do |sym|
          !sym.dummy? &&
          sym != @error &&
          sym != @start &&
          (!sym.reachable.include?(@start) || !productive_symbols.include?(sym)) &&
          none? { |rule| rule.explicit_precedence == sym }
        end
      end
    end

    # A 'nonproductive' Sym, if taken as a starting point and then converted
    # into a series of tokens by repeated substitution, would get stuck in an
    # infinite loop and never reach a point where only terminals were left
    # A 'productive' Sym, on the other hand, is not 'stuck' in an infinite loop
    #
    # (Even if it can be converted to an empty sequence of tokens; in other
    # words, if it is nullable, then it is considered 'productive')
    def productive_symbols
      raise 'Grammar not yet closed' unless @closed
      @productive_symbols ||= begin
        Sym.set_closure(@terminals + nullable_symbols.to_a)
      end
    end

    # Can an empty sequence of tokens reduce to this nonterminal?
    # (Can it be produced out of "nothing"?)
    def nullable_symbols
      raise 'Grammar not yet closed' unless @closed
      @nullable_symbols ||=
        Sym.set_closure(@symbols.select { |nt| nt.heads.any?(&:reduce?) })
    end

    private

    def add_start_rule
      # We don't ever actually reduce to the dummy symbol; it is just there
      # because every rule must have a target
      # When building the parser states, we manually set the state where the
      # first 'anchor' symbol is shifted to an 'accept state' -- one which
      # successfully ends the parse
      @rules.unshift(Rule.new(@dummy, [@start, @anchor, @anchor], UserAction.empty))
    end

    def fix_ident
      @rules.each_with_index(&:ident=)
      @rules.flat_map(&:ptrs).each_with_index(&:ident=)

      @terminals, @nonterminals = @symbols.partition(&:terminal?)
      @symbols = @terminals + @nonterminals
      # number Syms so terminals have the lower numbers
      @symbols.each_with_index(&:ident=)
    end

    def check_terminals
      # token declarations in Racc are optional
      # however, if you declare some tokens, you must declare them all
      if @symbols.any?(&:declared_as_terminal?)
        # any symbol which has no derivation rules is a terminal
        undeclared = terminals.reject do |t|
          t.declared_as_terminal? || t.string_symbol? || t.locate.empty?
        end
        undeclared -= [@anchor, @error]
        unless undeclared.empty?
          locations = undeclared.flat_map(&:locate).map(&:rule).uniq
          raise CompileError, "terminal#{'s' unless undeclared.one?} " \
            "#{Racc.to_sentence(undeclared)} #{undeclared.one? ? 'was' : 'were'} " \
            "not declared in a 'token' block:\n" <<
            Source::SparseLines.merge(locations.map(&:source)).map(&:spifferific).join("\n\n")
        end

        wrongly_declared = nonterminals.select(&:declared_as_terminal?)
        unless wrongly_declared.empty?
          bad_rules = wrongly_declared.flat_map(&:heads).map(&:rule)
          raise CompileError, "tokens #{Racc.to_sentence(wrongly_declared)} " \
            "were declared in a 'token' block, but they also have derivation " \
            "rules:\n" <<
            Source::SparseLines.merge(bad_rules.map(&:source)).map(&:spifferific).join("\n\n")
        end
      end

      bad_strings = @symbols.select { |s| s.string_symbol? && s.nonterminal? }
      unless bad_strings.empty?
        bad_rules = bad_strings.flat_map(&:heads).map(&:rule)
        raise CompileError, 'you may not create derivation rules for a ' \
          "string literal:\n" <<
          Source::SparseLines.merge(bad_rules.map(&:source)).map(&:spifferific).join("\n\n")
      end

      bad_prec = @symbols.select { |s| s.assoc && s.nonterminal? }
      unless bad_prec.empty?
        bad_rules = bad_prec.flat_map(&:heads).map(&:rule)
        raise CompileError, "tokens #{Racc.to_sentence(bad_prec)} appeared " \
          "in a prechigh/preclow block, but they are not terminals:\n" <<
          Source::SparseLines.merge(bad_rules.map(&:source)).map(&:spifferific).join("\n\n")
      end

      bad_prec = @rules.select do |rule|
        rule.explicit_precedence && rule.explicit_precedence.nonterminal?
      end
      unless bad_prec.empty?
        raise CompileError, "The following rule#{'s' unless bad_prec.one?} " \
          "use#{'s' if bad_prec.one?} nonterminals for explicit precedence, " \
          "which is not allowed:\n" <<
          Source::SparseLines.merge(bad_prec.map(&:source)).map(&:spifferific).join("\n\n")
      end
    end

    def check_rules
      @rules.group_by(&:target).each_value do |same_lhs|
        same_lhs.group_by(&:symbols).each_value do |same_rhs|
          next unless same_rhs.size > 1
          raise CompileError, "The following rules are duplicates:\n" <<
            Source::SparseLines.merge(same_rhs.map(&:source)).map(&:spifferific).join("\n\n")
        end
      end
    end
  end

  class Rule
    def initialize(target, syms, act, source = nil, precedence = nil)
      @target  = target # LHS of rule (may be `nil` if not yet known)
      @symbols = syms  # RHS of rule
      @action  = act    # run this code when reducing
      @alternatives = []
      @source = source

      @ident = nil
      @precedence = precedence
      @precedence_used = false # does explicit precedence actually resolve conflicts?

      @ptrs = (0..@symbols.size).map { |idx| LocationPointer.new(self, idx) }
      @ptrs.freeze

      # reverse lookup from each Sym in RHS to location in rule where it appears
      @symbols.each_with_index { |sym, idx| sym.locate << @ptrs[idx] }

      # reverse lookup from LHS of rule to starting location in rule
      @target.heads << @ptrs[0] if @target
    end

    attr_accessor :ident
    attr_reader :source
    attr_reader :symbols
    attr_reader :action
    attr_reader :target
    attr_reader :ptrs

    def target=(target)
      raise 'target already set' if @target
      @target = target
      @target.heads << @ptrs[0]
    end

    def |(x)
      @alternatives.push x.rule
      self
    end

    def rule
      self
    end

    def each_rule(&block)
      yield self
      @alternatives.each(&block)
    end

    def precedence
      @precedence || @symbols.select(&:terminal?).last
    end

    def explicit_precedence
      @precedence
    end

    def explicit_precedence_used!
      @precedence_used = true
    end

    def explicit_precedence_used?
      @precedence_used
    end

    def inspect
      "#<Racc::Rule id=#{@ident} #{display}>"
    end

    def to_s
      if @source
        @source.spifferific
      else
        display
      end
    end

    def display
      rule = "#{@target} : #{@symbols.reject(&:hidden).map(&:to_s).join(' ')}"
      if @precedence
        rule << ' ' << Color.explicit_prec('=' << @precedence.display_name)
      end
      rule
    end

    def each(&block)
      @symbols.each(&block)
    end

    def [](idx)
      @symbols[idx]
    end

    def size
      @symbols.size
    end

    # is this the 'end' rule which is applied last in a successful parse?
    def accept?
      @symbols.last && @symbols.last.anchor?
    end

    # sometimes a Rule is instantiated before the target is actually known
    # it may be given a "placeholder" target first, which is later replaced
    # with the real one
    def replace(placeholder, actual)
      raise 'wrong placeholder' if placeholder != @target
      @target.heads.delete(ptrs[0]) if @target
      @target = actual
      @target.heads << @ptrs[0]
      @symbols.map! { |s| s == placeholder ? actual : s }
    end
  end

  class UserAction
    def UserAction.source_text(src, lineno)
      new(src, nil).tap { |act| act.lineno = lineno }
    end

    def UserAction.proc(pr = nil, &block)
      if pr and block
        raise ArgumentError, "both of argument and block given"
      end
      new(nil, pr || block)
    end

    def UserAction.empty
      new(nil, nil)
    end

    private_class_method :new

    def initialize(src, proc)
      @source = src
      @proc = proc
    end

    attr_reader :source
    attr_reader :proc
    attr_accessor :lineno

    def source?
      not @proc
    end

    def empty?
      not @proc and not @source
    end

    def to_s
      "{action type=#{@source || @proc || 'nil'}}"
    end

    alias inspect to_s
  end

  class OrMark < Struct.new(:lineno)
    def to_s
      '|'
    end
  end

  class Prec < Struct.new(:symbol, :range)
    def to_s
      Color.explicit_prec(range.text)
    end

    def lineno
      range.lineno
    end
  end

  # A combination of a rule and a position in its RHS
  # Note that the number of pointers is more than the rule's RHS array,
  # because it points to the right edge of the final symbol when reducing
  #
  class LocationPointer
    def initialize(rule, i)
      @rule  = rule
      @index = i
      @ident = nil # canonical ordering for all LocationPointers
    end

    attr_reader :rule
    attr_reader :index
    attr_accessor :ident

    # Sym which immediately follows this position in RHS
    # or nil if it points to the end of RHS
    def symbol
      @rule.symbols[@index]
    end

    def to_s
      result = "#{@rule.target} : "
      if @index > 0
        result << "#{@rule.symbols[0...@index].reject(&:hidden).map(&:to_s).join(' ')} ."
      else
        result << '.'
      end
      unless reduce?
        result << " #{rule.symbols[@index..-1].reject(&:hidden).map(&:to_s).join(' ')}"
      end
      if sym = @rule.explicit_precedence
        result << ' ' << Color.explicit_prec('=' << sym.display_name)
      end
      result
    end

    alias inspect to_s

    def head?
      @index == 0
    end

    def next
      @rule.ptrs[@index + 1] or ptr_bug!
    end

    def reduce?
      symbol.nil?
    end

    private

    def ptr_bug!
      raise "racc: fatal: pointer doesn't exist: self: #{to_s}"
    end
  end

  # A terminal or nonterminal symbol
  class Sym
    def initialize(value, grammar, dummy)
      @ident   = nil
      @value   = value
      @dummy   = dummy
      @grammar = grammar

      @declared_terminal = false
      @precedence = nil

      case value
      when Symbol
        @display_name = value.to_s
        @serialized = value.inspect
        @string = false
      when String
        @display_name = @serialized = value.inspect
        @string = true
      when false
        @display_name = '$end'
        @serialized = 'false'
        @string = false
      else
        raise ArgumentError, "illegal symbol value: #{value.class}"
      end

      @heads   = [] # RHS of rules which can reduce to this Sym
      @locate  = [] # all locations where this Sym appears on RHS of a rule
      @hidden  = false # don't show in diagnostic messages
    end

    attr_reader :value
    attr_accessor :ident
    alias hash ident

    attr_accessor :display_name
    attr_accessor :precedence
    attr_accessor :assoc
    attr_accessor :hidden

    # some tokens are written one way in the grammar, but the actual value
    # expected from the lexer is different
    # you can set this up using a 'convert' block
    attr_accessor :serialized

    attr_reader :heads
    attr_reader :locate

    # Find a set of Syms with a common property
    # The property extends to any Sym, which has a derivation rule whose RHS
    # consists entirely of Syms with the property
    def self.set_closure(seed)
      Racc.set_closure(seed) do |sym, set|
        rules = sym.locate.map(&:rule)
        rules.select { |r| r.symbols.all? { |s| set.include?(s) }}.map(&:target)
      end
    end

    def dummy?
      @dummy
    end

    def terminal?
      heads.empty?
    end

    def nonterminal?
      !heads.empty?
    end

    def declared_as_terminal!
      @declared_terminal = true
    end

    def declared_as_terminal?
      @declared_terminal
    end

    # is this a terminal which is written as a string literal in the grammar?
    # (if so, it shouldn't appear on the LHS of any rule)
    def string_symbol?
      @string
    end

    def to_s
      return @display_name.dup unless Color.enabled?
      if string_symbol?
        Color.string(@display_name)
      elsif terminal?
        Color.terminal(@display_name)
      else
        Color.nonterminal(@display_name)
      end
    end

    def inspect
      "<Sym #{value ? value.inspect : '$end'}>"
    end

    def |(x)
      rule() | x.rule
    end

    def rule
      Rule.new(nil, [self], UserAction.empty)
    end

    def nullable?
      @nullable ||= @grammar.nullable_symbols.include?(self)
    end

    # What NTs can be reached from this symbol, by traversing from the RHS of
    # a rule where the symbol appears, to the target of the rule, then to the
    # RHS of its rules, and so on?
    def reachable
      @reachable ||= Racc.set_closure(@locate.map { |ptr| ptr.rule.target }) do |sym|
        sym.locate.map { |ptr| ptr.rule.target }
      end
    end

    # If an instance of this NT comes next, then what rules could we be
    # starting?
    def expand
      @expand ||= Racc.set_closure(@heads.dup) do |ptr|
        if (sym = ptr.symbol) && sym.nonterminal?
          sym.heads
        end
      end
    end

    # What terminals/NT could appear first in a series of terminals/NTs which
    # reduce to this symbol?
    def first_set
      @first_set ||= Racc.set_closure([self]) do |sym|
        sym.heads.each_with_object([]) do |ptr, next_syms|
          while !ptr.reduce?
            next_syms << ptr.symbol
            ptr.symbol.nullable? ? ptr = ptr.next : break
          end
        end
      end
    end
  end
end
