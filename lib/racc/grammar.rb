# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".

require 'racc/sourcetext'
require 'racc/logfilegenerator'
require 'racc/exception'
require 'forwardable'
require 'set'

module Racc

  class Grammar

    def initialize(debug_flags = DebugFlags.new)
      @symboltable = SymbolTable.new
      @debug_symbol = debug_flags.token
      @rules   = []  # :: [Rule]
      @start   = nil
      @n_expected_srconflicts = nil
      @prec_table = []
      @prec_table_closed = false
      @closed = false
      @states = nil
    end

    attr_reader :start
    attr_reader :symboltable
    attr_reader :n_expected_srconflicts

    def [](x)
      @rules[x]
    end

    def each_rule(&block)
      @rules.each(&block)
    end

    alias each each_rule

    def each_index(&block)
      @rules.each_index(&block)
    end

    def each_with_index(&block)
      @rules.each_with_index(&block)
    end

    def size
      @rules.size
    end

    def to_s
      "<Racc::Grammar>"
    end

    extend Forwardable

    def_delegator "@symboltable", :each, :each_symbol
    def_delegator "@symboltable", :each_terminal
    def_delegator "@symboltable", :each_nonterminal

    def intern(value, dummy = false)
      @symboltable.intern(value, dummy)
    end

    def symbols
      @symboltable.symbols
    end

    def nonterminal_base
      @symboltable.nt_base
    end

    def useless_nonterminal_exist?
      n_useless_nonterminals() != 0
    end

    def n_useless_nonterminals
      @n_useless_nonterminals ||= @symboltable.nonterminals.count(&:useless?)
    end

    def useless_rule_exist?
      n_useless_rules() != 0
    end

    def n_useless_rules
      @n_useless_rules ||= @rules.count(&:useless?)
    end

    def n_expected_srconflicts=(value)
      if @n_expected_srconflicts
        raise CompileError, "'expect' seen twice"
      end
      @n_expected_srconflicts = value
    end

    def nfa
      (@states ||= States.new(self)).nfa
    end

    def dfa
      (@states ||= States.new(self)).dfa
    end

    alias states dfa

    def state_transition_table
      states().state_transition_table
    end

    def parser_class
      states = states()   # cache
      if $DEBUG
        srcfilename = caller(1).first.slice(/\A(.*?):/, 1)
        begin
          write_log srcfilename + ".output"
        rescue SystemCallError
        end
        report = lambda {|s| $stderr.puts "racc: #{srcfilename}: #{s}" }
        if states.should_report_srconflict?
          report["#{states.n_srconflicts} shift/reduce conflicts"]
        end
        if states.rrconflict_exist?
          report["#{states.n_rrconflicts} reduce/reduce conflicts"]
        end
        g = states.grammar
        if g.useless_nonterminal_exist?
          report["#{g.n_useless_nonterminals} useless nonterminals"]
        end
        if g.useless_rule_exist?
          report["#{g.n_useless_rules} useless rules"]
        end
      end
      states.state_transition_table.parser_class
    end

    def write_log(path)
      File.open(path, 'w') {|f|
        LogFileGenerator.new(states()).output f
      }
    end

    #
    # Grammar Definition Interface
    #

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

    #
    # Dynamic Generation Interface
    #

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
        @grammar.each do |rule|
          if rule.specified_prec
            rule.specified_prec = @grammar.intern(rule.specified_prec)
          end
        end
        @grammar.init
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
        _add target, args.first
      end

      def _add(target, x)
        case x
        when Sym
          @delayed.each do |rule|
            rule.replace x, target if rule.target == x
          end
          @grammar.symboltable.delete x
        else
          x.each_rule do |r|
            r.target = target
            @grammar.add r
          end
        end
        flush_delayed
      end

      def _delayed_add(rule)
        @delayed.push rule
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
        _delayed_add Rule.new(wrapper,
                              [wrapped],
                              UserAction.proc(block))
        wrapper
      end
    end

    #
    # Computation
    #

    def init
      return if @closed
      @closed = true
      # if 'start' nonterminal was not explicitly set, just take the first one
      @start ||= @rules.map(&:target).detect { |sym| !sym.dummy? }
      fail CompileError, 'no rule in input' if @rules.empty?
      add_start_rule
      @rules.freeze
      fix_ident
      compute_hash
      compute_heads
      determine_terminals
      @symboltable.fix
      compute_locate
      @symboltable.each_nonterminal {|t| compute_expand t }
      compute_nullable
      compute_useless
    end

    private

    def add_start_rule
      r = Rule.new(@symboltable.dummy,
                   [@start, @symboltable.anchor, @symboltable.anchor],
                   UserAction.empty)
      r.ident = 0
      r.hash = 0
      r.precedence = nil
      @rules.unshift r
    end

    # Rule#ident
    def fix_ident
      @rules.each_with_index(&:ident=)
    end

    # Rule#hash
    def compute_hash
      hash = 4   # size of dummy rule
      @rules.each do |rule|
        rule.hash = hash
        hash += (rule.size + 1)
      end
    end

    # Sym#heads
    def compute_heads
      @rules.each do |rule|
        rule.target.heads.push rule.ptrs[0]
      end
    end

    # Sym#terminal?
    def determine_terminals
      @symboltable.each do |s|
        s.term = s.heads.empty?
      end
    end

    # Sym#locate
    def compute_locate
      @rules.each do |rule|
        t = nil
        rule.ptrs.each do |ptr|
          unless ptr.reduce?
            tok = ptr.symbol
            tok.locate.push ptr
            t = tok if tok.terminal?
          end
        end
        rule.precedence = t
      end
    end

    # Sym#expand
    def compute_expand(t)
      puts "expand> #{t.to_s}" if @debug_symbol
      t.expand = _compute_expand(t, Set.new, [])
      puts "expand< #{t.to_s}: #{t.expand.to_s}" if @debug_symbol
    end

    def _compute_expand(t, set, lock)
      if tmp = t.expand
        return set.merge(tmp)
      end

      tok = nil
      t.heads.each { |ptr| set.add(ptr) }
      t.heads.each do |ptr|
        tok = ptr.symbol
        if tok and tok.nonterminal?
          unless lock[tok.ident]
            lock[tok.ident] = true
            _compute_expand tok, set, lock
          end
        end
      end
      set
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
    # A 'useless' Sym is a nonterminal which can never be part of a valid parse
    # tree, because there is no sequence of rules by which that nonterminal
    # could eventually reduce down to the 'start' node
    def compute_useless
      @symboltable.each_terminal { |sym| sym.useless = false }
      @symboltable.each_nonterminal { |sym| sym.useless = true }

      @symboltable.error.useless = false
      @symboltable.dummy.useless = false
      @symboltable.anchor.useless = false
      @start.useless = false
      worklist = @start.heads.dup # all RHS of rules which reduce to 'start' NT

      until worklist.empty?
        rule = worklist.shift.rule
        rule.symbols.each do |sym|
          if sym.useless?
            sym.useless = false
            worklist.concat(sym.heads)
          end
        end
      end
    end
  end

  class Rule
    def initialize(target, syms, act)
      @target = target # LHS of rule (may be `nil` if not yet known)
      @symbols = syms  # RHS of rule
      @action = act    # run this code when reducing
      @alternatives = []

      @ident = nil
      @hash = nil
      @precedence = nil
      @specified_prec = nil
      @useless = nil

      @ptrs = (0..@symbols.size).map do |idx|
        LocationPointer.new(self, idx)
      end
    end

    attr_accessor :target
    attr_reader :symbols
    attr_reader :action

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

    attr_accessor :ident
    attr_accessor :hash
    attr_reader :ptrs

    def precedence
      @specified_prec || @precedence
    end

    def precedence=(sym)
      @precedence ||= sym
    end

    def prec(sym, &block)
      @specified_prec = sym
      if block
        unless @action.empty?
          raise CompileError, 'both of rule action block and prec block given'
        end
        @action = UserAction.proc(block)
      end
      self
    end

    attr_accessor :specified_prec

    def useless?
      @useless
    end

    def useless=(u)
      @useless = u
    end

    def inspect
      "#<Racc::Rule id=#{@ident} (#{@target})>"
    end

    def [](idx)
      @symbols[idx]
    end

    def size
      @symbols.size
    end

    def empty?
      @symbols.empty?
    end

    def to_s
      "#<rule#{@ident}>"
    end

    def accept?
      if tok = @symbols[-1]
        tok.anchor?
      else
        false
      end
    end

    def each(&block)
      @symbols.each(&block)
    end

    def replace(src, dest)
      @target = dest
      @symbols = @symbols.map {|s| s == src ? dest : s }
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
    end

    attr_reader :rule
    attr_reader :index

    # Sym which immediately follows this position in RHS
    # or nil if it points to the end of RHS
    def symbol
      @rule.symbols[@index]
    end

    def hash
      @rule.hash + @index
    end

    def to_s
      sprintf('(%d,%d %s)', @rule.ident, @index, (reduce? ? '#' : symbol.to_s))
    end

    alias inspect to_s

    def head?
      @index == 0
    end

    def next
      @rule.ptrs[@index + 1] or ptr_bug!
    end

    def before(len)
      @rule.ptrs[@index - len] or ptr_bug!
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

    attr_reader :symbols
    alias to_a symbols

    def delete(sym)
      @symbols.delete(sym)
      @cache.delete(sym.value)
    end

    attr_reader :nt_base

    def nt_max
      @symbols.size
    end

    def each(&block)
      @symbols.each(&block)
    end

    def terminals
      @terms
    end

    def each_terminal(&block)
      @terms.each(&block)
    end

    def nonterminals
      @symbols[@nt_base, @symbols.size - @nt_base]
    end

    def each_nonterminal(&block)
      @nterms.each(&block)
    end

    def fix
      @terms, @nterms = @symbols.partition {|s| s.terminal? }
      @symbols = @terms + @nterms
      @nt_base = @terms.size
      fix_ident
      check_terminals
    end

    private

    def fix_ident
      @symbols.each_with_index(&:ident=)
    end

    def check_terminals
      return unless @symbols.any? {|s| s.should_terminal? }
      @anchor.should_terminal
      @error.should_terminal
      each_terminal do |t|
        t.should_terminal if t.string_symbol?
      end
      each do |s|
        s.should_terminal if s.assoc
      end
      terminals().reject {|t| t.should_terminal? }.each do |t|
        raise CompileError, "terminal #{t} not declared as terminal"
      end
      nonterminals().select {|n| n.should_terminal? }.each do |n|
        raise CompileError, "symbol #{n} declared as terminal but is not terminal"
      end
    end
  end

  # Stands terminal and nonterminal symbols.
  class Sym

    def initialize(value, dummyp)
      @ident = nil
      @value = value
      @dummyp = dummyp

      @term  = nil
      @should_terminal = false
      @precedence = nil
      case value
      when Symbol
        @to_s = value.to_s
        @serialized = value.inspect
        @string = false
      when String
        @to_s = value.inspect
        @serialized = value.dump
        @string = true
      when false
        @to_s = '$end'
        @serialized = 'false'
        @string = false
      when ErrorSymbolValue
        @to_s = 'error'
        @serialized = 'Object.new'
        @string = false
      else
        raise ArgumentError, "unknown symbol value: #{value.class}"
      end

      @heads   = [] # RHS of rules which can reduce to this Sym
      @locate  = [] # all rules which have this Sym on their RHS
      @null    = nil
      @expand  = nil
      @useless = nil
    end

    class << self
      def once_writer(nm)
        nm = nm.id2name
        module_eval(<<-EOS)
          def #{nm}=(v)
            raise 'racc: fatal: @#{nm} != nil' unless @#{nm}.nil?
            @#{nm} = v
          end
        EOS
      end
    end

    once_writer :ident
    attr_reader :ident

    alias hash ident

    attr_reader :value

    def dummy?
      @dummyp
    end

    def terminal?
      @term
    end

    def nonterminal?
      !@term
    end

    def term=(t)
      raise 'racc: fatal: term= called twice' unless @term.nil?
      @term = t
    end

    def should_terminal
      @should_terminal = true
    end

    def should_terminal?
      @should_terminal
    end

    def string_symbol?
      @string
    end

    def serialize
      @serialized
    end

    # some tokens are written one way in the grammar, but the actual value
    # expected from the lexer is different
    # you can set this up using a 'convert' block
    attr_writer :serialized

    attr_accessor :precedence
    attr_accessor :assoc

    def to_s
      @to_s.dup
    end

    alias inspect to_s

    def |(x)
      rule() | x.rule
    end

    def rule
      Rule.new(nil, [self], UserAction.empty)
    end

    #
    # cache
    #

    attr_reader :heads
    attr_reader :locate

    def nullable?
      @null
    end

    def null=(n)
      @null = n
    end

    attr_reader :expand
    once_writer :expand

    def useless?
      @useless
    end

    def useless=(f)
      @useless = f
    end
  end
end
