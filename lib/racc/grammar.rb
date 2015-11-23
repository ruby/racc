# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".

require 'racc/source_text'
require 'racc/log_file_generator'
require 'racc/exception'
require 'racc/color'
require 'set'

module Racc
  class Grammar
    include Enumerable

    def initialize(filename = nil)
      @symboltable = SymbolTable.new
      @filename = filename
      @rules = []
      @start = nil
      @n_expected_srconflicts = nil
      @prec_table = []
      @prec_table_closed = false
      @closed = false
      @states = States.new(self)
    end

    attr_reader :states
    attr_reader :start
    attr_reader :symboltable
    attr_reader :n_expected_srconflicts

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

    def intern(value, dummy = false)
      @symboltable.intern(value, dummy)
    end

    def symbols
      @symboltable.symbols
    end

    def nonterminal_base
      @symboltable.nt_base
    end

    def useless_nonterminals
      @symboltable.nonterminals.select(&:useless?)
    end

    def sr_conflicts
      @states.sr_conflicts
    end

    def rr_conflicts
      @states.rr_conflicts
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

    def warnings
      warnings = []

      @symboltable.each do |sym|
        next unless sym.useless?

        if sym.locate.empty?
          what = sym.terminal? ? 'terminal' : 'nonterminal'
          warnings << "Useless #{what} #{sym} does not appear on the " \
            ' right side of any rule, neither is it the start symbol.'
        elsif sym.can_derive.include?(sym)
          if sym.can_derive.one?
            warnings << "Useless nonterminal #{sym} only appears on " \
              'the right side of its own rules.'
          else
            warnings << "Useless nonterminal #{sym} cannot be part " \
              'of a valid parse tree, since there is no sequence of ' \
              ' reductions from it to the start symbol. It can only reduce ' \
              "to: #{sym.can_derive.map(&:to_s).join(', ')}"
          end
        end
      end

      warnings.concat(@states.warnings)
    end

    # Grammar Definition Interface

    def add(rule)
      raise ArgumentError, "rule added after the Grammar closed" if @closed
      @rules.push rule
    end

    def added?(sym)
      @rules.detect {|r| r.target == sym }
    end

    def start_symbol=(s)
      raise CompileError, "start symbol set twice'" if @start
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

    # Dynamic Generation Interface

    def Grammar.define(&block)
      env = DefinitionEnv.new
      env.instance_eval(&block)
      env.grammar
    end

    # Implements `Grammar.define` DSL
    # Methods are DSL 'keywords' which can be used in a `Grammar.define` block
    #
    # Key method is `#seq`, which creates a `Rule` (effectively, RHS of a rule in a BNF grammar)
    # (`Rule` objects can be combined using `#|`, similar to how alternative derivations for a
    # non-terminal are separated by | in a BNF grammar)
    #
    # The other key method is `#method_missing`, which is used to register rules like so:
    #
    #     self.nonterminal_name = seq(:token, :another_token) | seq(:something_else)
    #
    class DefinitionEnv
      def initialize
        @grammar = Grammar.new
        @seqs = Hash.new(0)
        @delayed = []
      end

      def grammar
        flush_delayed
        @grammar.finished!
        @grammar
      end

      # Intercept calls to `self.non_terminal = ...`, and use them to register
      # a new rule
      def method_missing(mid, *args, &block)
        unless mid.to_s[-1,1] == '='
          super   # raises NoMethodError
        end
        target = @grammar.intern(mid.to_s.chop.intern)
        unless args.size == 1
          raise ArgumentError, "too many arguments for #{mid} (#{args.size} for 1)"
        end
        _add(target, args.first)
      end

      # We just received a call to `self.nonterminal = definition`
      # But when we were executing that "definition", we didn't know what the
      # nonterminal on the LHS would be
      # Depending on the DSL method(s) which were used in the "definition",
      # `rhs` may be:
      # - A "placeholder" target symbol, which should be replaced with the
      #   "real" target in all the rules which the definition created
      # - A `Rule`, whose target we didn't know at the time of definition.
      #   Its target will be `nil` right now; fix that up.
      def _add(target, rhs)
        case rhs
        when Sym
          @delayed.each do |rule|
            rule.replace(rhs, target) if rule.target == rhs
          end
          @grammar.symboltable.delete(rhs)
        else
          rhs.each_rule do |rule|
            rule.target = target
            @grammar.add(rule)
          end
        end
        flush_delayed
      end

      def _delayed_add(rule)
        @delayed.push(rule)
      end

      def _added?(sym)
        @grammar.added?(sym) or @delayed.detect {|r| r.target == sym }
      end

      def flush_delayed
        return if @delayed.empty?
        @delayed.each do |rule|
          @grammar.add rule
        end
        @delayed.clear
      end

      # Basic method for creating a new `Rule`.
      def seq(*list, &block)
        Rule.new(nil, list.map {|x| _intern(x) }, UserAction.proc(block))
      end

      # Create a null `Rule` (one with an empty RHS)
      def null(&block)
        seq(&block)
      end

      # Create a `Rule` which can either be null (like an empty RHS in a BNF grammar),
      # in which case the action will return `default`, or which can match a single
      # `sym`.
      def option(sym, default = nil, &block)
        _defmetasyntax("option", _intern(sym), block) {|target|
          seq() { default } | seq(sym)
        }
      end

      # Create a `Rule` which matches 0 or more instance of `sym` in a row.
      def many(sym, &block)
        _defmetasyntax("many", _intern(sym), block) {|target|
            seq() { [] }\
          | seq(target, sym) {|list, x| list.push x; list }
        }
      end

      # Create a `Rule` which matches 1 or more instances of `sym` in a row.
      def many1(sym, &block)
        _defmetasyntax("many1", _intern(sym), block) {|target|
            seq(sym) {|x| [x] }\
          | seq(target, sym) {|list, x| list.push x; list }
        }
      end

      # Create a `Rule` which matches 0 or more instances of `sym`, separated
      # by `sep`.
      def separated_by(sep, sym, &block)
        option(separated_by1(sep, sym), [], &block)
      end

      # Create a `Rule` which matches 1 or more instances of `sym`, separated
      # by `sep`.
      def separated_by1(sep, sym, &block)
        _defmetasyntax("separated_by1", _intern(sym), block) {|target|
            seq(sym) {|x| [x] }\
          | seq(target, sep, sym) {|list, _, x| list.push x; list }
        }
      end

      def _intern(x)
        case x
        when Symbol, String
          @grammar.intern(x)
        when Racc::Sym
          x
        else
          raise TypeError, "wrong type #{x.class} (expected Symbol/String/Racc::Sym)"
        end
      end

      private

      # the passed block will define a `Rule` (which may be chained with
      # 'alternative' `Rule`s)
      # make all of those rules reduce to a placeholder nonterminal,
      # executing `action` when they do so,
      # and return the newly generated placeholder
      #
      # (when the placeholder is associated with a "real" nonterminal using the
      # `self.non_terminal = ...` syntax, we will go through all the generated
      # rules and rewrite the placeholder to the "real" nonterminal)
      #
      def _defmetasyntax(type, id, action, &block)
        if action
          idbase = :"#{type}@#{id}-#{@seqs[type] += 1}"
          _regist(:"#{idbase}-core", &block)
          _wrap(idbase, :"#{idbase}-core", action)
        else
          _regist(:"#{type}@#{id}", &block)
        end
      end

      def _regist(target)
        sym = @grammar.intern(target)
        unless _added?(sym)
          yield(target).each_rule do |rule|
            rule.target = sym
            _delayed_add(rule)
          end
        end
        sym
      end

      # create a rule which reduces wrapped -> wrapper and executes an
      # action at the same time
      # (this is a way to make sure an action is executed everytime a
      # reduction is done using a particular generated rule)
      def _wrap(wrapper, wrapped, block)
        wrapped = @grammar.intern(wrapped)
        wrapper = @grammar.intern(wrapper)
        _delayed_add Rule.new(wrapper, [wrapped], UserAction.proc(block))
        wrapper
      end
    end

    # Computation

    def finished!
      return if @closed
      @closed = true

      # if 'start' nonterminal was not explicitly set, just take the first one
      @start ||= @rules.map(&:target).detect { |sym| !sym.dummy? }
      fail CompileError, 'no rule in input' if @rules.empty?
      add_start_rule
      @rules.freeze

      fix_ident
      compute_nullable
      compute_useless
    end

    private

    def add_start_rule
      r = Rule.new(@symboltable.dummy,
                   [@start, @symboltable.anchor, @symboltable.anchor],
                   UserAction.empty)
      @rules.unshift(r)
    end

    # Rule#ident
    def fix_ident
      @rules.each_with_index(&:ident=)
      @rules.flat_map(&:ptrs).each_with_index(&:ident=)
      @symboltable.fix_ident
    end

    # Sym#nullable?
    # Can an empty sequence of tokens reduce to this nonterminal?
    # (Can it be produced out of "nothing"?)
    def compute_nullable
      @symboltable.each { |t| t.null = false }

      worklist = []
      @symboltable.nonterminals.each do |sym|
        if sym.heads.any?(&:reduce?)
          sym.null = true
          worklist.concat(sym.locate)
        end
      end

      until worklist.empty?
        rule = worklist.shift.rule
        if !rule.target.nullable? && rule.symbols.all?(&:nullable?)
          rule.target.null = true
          worklist.concat(rule.target.locate)
        end
      end
    end

    # Sym#useless?
    # A 'useless' Sym is one which can never be part of a valid parse
    # tree, because there is no sequence of rules by which it
    # could eventually reduce down to the 'start' node
    def compute_useless
      @symboltable.each do |sym|
        sym.useless = !sym.dummy? &&
                      sym != @symboltable.error &&
                      sym != @start &&
                      !sym.can_derive.include?(@start)
      end
    end
  end

  class Rule
    def initialize(target, syms, act, precedence = nil)
      @target = target # LHS of rule (may be `nil` if not yet known)
      @symbols = syms  # RHS of rule
      @action = act    # run this code when reducing
      @alternatives = []

      @ident = nil
      @precedence = precedence

      @ptrs = (0..@symbols.size).map { |idx| LocationPointer.new(self, idx) }

      # reverse lookup from each Sym in RHS to location in rule where it appears
      @symbols.each_with_index { |sym, idx| sym.locate << @ptrs[idx] }

      # reverse lookup from LHS of rule to starting location in rule
      @target.heads << @ptrs[0] if @target
    end

    attr_accessor :ident
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

    def inspect
      "#<Racc::Rule id=#{@ident} (#{@target})>"
    end

    def to_s
      "#{@target} : #{@symbols.map(&:to_s).join(' ')}"
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
    def UserAction.source_text(src)
      new(src, nil)
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

  class Prec < Struct.new(:symbol, :lineno)
    def to_s
      "=#{@symbol}"
    end
  end

  # A combination of a rule and a position in its RHS.
  # Note that the number of pointers is more than the rule's RHS array,
  # because pointer points to the right edge of the final symbol when reducing.
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
      result = "#{@rule.target} : " \
        "#{@rule.symbols[0...@index].map(&:to_s).join(' ')} ."
      unless reduce?
        result << " #{rule.symbols[@index..-1].map(&:to_s).join(' ')}"
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
      raise "racc: fatal: pointer not exist: self: #{to_s}"
    end
  end

  class SymbolTable
    include Enumerable

    def initialize
      @symbols = [] # all Syms used in a grammar
      @cache   = {} # map of String/Symbol name -> Sym

      # 'dummy' and 'anchor' are used to make sure the parser runs over ALL the
      # input tokens before concluding that the parse was successful
      # an 'anchor' token is appended to the end of the token stream, and a
      # 'dummy rule' is automatically added which reduces [start node, anchor]
      # to 'dummy'
      # only if the parse ends in 'dummy', is it considered successful

      @dummy   = intern(:$start, true)
      @anchor  = intern(false, true)   # Symbol ID = 0
      @error   = intern(:error, false) # Symbol ID = 1
    end

    attr_reader :dummy
    attr_reader :anchor
    attr_reader :error

    def [](id)
      @symbols[id]
    end

    def intern(val, dummy = false)
      @cache[val] ||= begin
        Sym.new(val, dummy).tap { |sym| @symbols.push(sym) }
      end
    end

    attr_reader :terminals
    attr_reader :nonterminals
    attr_reader :symbols

    def delete(sym)
      @symbols.delete(sym)
      @cache.delete(sym.value)
    end

    def nt_base
      @terminals.size
    end

    def each(&block)
      @symbols.each(&block)
    end

    def fix_ident
      @terminals, @nonterminals = @symbols.partition(&:terminal?)
      @symbols = @terminals + @nonterminals
      # number Syms so terminals have the lower numbers
      @symbols.each_with_index(&:ident=)
      check_terminals
    end

    private

    def check_terminals
      # token declarations in Racc are optional
      # however, if you declare some tokens, you must declare them all
      return unless @symbols.any?(&:should_be_terminal?)
      @anchor.should_be_terminal!
      @error.should_be_terminal!
      terminals.select(&:string_symbol?).each(&:should_be_terminal!)
      select(&:assoc).each(&:should_be_terminal!)
      terminals.reject(&:should_be_terminal?).each do |t|
        raise CompileError, "terminal #{t} not declared as terminal"
      end
      nonterminals.select(&:should_be_terminal?).each do |n|
        raise CompileError, "symbol #{n} declared as terminal but is not terminal"
      end
    end
  end

  # Stands terminal and nonterminal symbols.
  class Sym
    def initialize(value, dummy)
      @ident  = nil
      @value  = value
      @dummy  = dummy

      @should_be_terminal = false
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
        raise ArgumentError, "unknown symbol value: #{value.class}"
      end

      @heads   = [] # RHS of rules which can reduce to this Sym
      @locate  = [] # all rules which have this Sym on their RHS
      @null    = false
      @useless = false
    end

    attr_reader :value
    attr_accessor :ident
    alias hash ident

    attr_accessor :display_name
    attr_accessor :precedence
    attr_accessor :assoc

    # some tokens are written one way in the grammar, but the actual value
    # expected from the lexer is different
    # you can set this up using a 'convert' block
    attr_accessor :serialized

    attr_reader :heads
    attr_reader :locate

    def dummy?
      @dummy
    end

    def terminal?
      heads.empty?
    end

    def nonterminal?
      !heads.empty?
    end

    def should_be_terminal!
      @should_be_terminal = true
    end

    # has this Sym appeared in a token declaration, or in some other context
    # where only a terminal should be used (such as associativity declaration)?
    def should_be_terminal?
      @should_be_terminal
    end

    # is this a terminal which is written as a string literal in the grammar?
    # (if so, it shouldn't appear on the LHS of any rule)
    def string_symbol?
      @string
    end

    def to_s
      return @display_name.dup unless Color.enabled?
      if terminal?
        if string_symbol?
          Color.yellow(@display_name)
        else
          Color.light_green(@display_name)
        end
      else
        Color.light_purple(@display_name)
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
      @null
    end

    def null=(n)
      @null = n
    end

    def useless?
      @useless
    end

    def useless=(f)
      @useless = f
    end

    # What NTs can this Sym be reduced down to (perhaps indirectly)?
    def can_derive
      @can_derive ||= begin
        worklist = @locate.map { |ptr| ptr.rule.target }
        result   = Set.new

        until worklist.empty?
          sym = worklist.shift
          if result.add?(sym)
            worklist.concat(sym.locate.map { |ptr| ptr.rule.target })
          end
        end

        result
      end
    end

    # If an instance of this NT comes next, then what rules could we be
    # starting?
    def expand
      @expand ||= begin
        worklist = @heads.dup
        result   = Set.new

        until worklist.empty?
          ptr = worklist.shift
          if result.add?(ptr)
            if (tok = ptr.symbol) && tok.nonterminal?
              worklist.concat(tok.heads)
            end
          end
        end

        result
      end
    end
  end
end
