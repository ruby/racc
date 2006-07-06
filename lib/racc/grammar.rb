#
# $Id$
#
# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".
#

require 'racc/compat'
require 'racc/iset'
require 'racc/sourcetext'
require 'racc/logfilegenerator'
require 'racc/exception'
require 'forwardable'

module Racc

  class Grammar

    def Grammar.define(&block)
      g = new()
      g.instance_eval(&block)
      g
    end

    def initialize(debug_flags = DebugFlags.new)
      @symboltable = SymbolTable.new
      @debug_symbol = debug_flags.token
      @rules   = []  # :: [Rule]
      @start   = nil
      @embedded_action_seq = 1
      @n_expected_srconflicts = nil
      @prec_table = []
      @prec_table_closed = false
      @closed = false
      @states = nil
    end

    attr_reader :start
    attr_reader :symboltable
    attr_accessor :n_expected_srconflicts

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

    def intern(value)
      @symboltable.intern(value)
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
      @n_useless_nonterminals ||=
          begin
            n = 0
            @symboltable.each_nonterminal do |sym|
              n += 1 if sym.useless?
            end
            n
          end
    end

    def useless_rule_exist?
      n_useless_rules() != 0
    end

    def n_useless_rules
      @n_useless_rules ||=
          begin
            n = 0
            each do |r|
              n += 1 if r.useless?
            end
            n
          end
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
      states().state_transition_table.parser_class
    end

    def write_log(path)
      File.open(path, 'w') {|f|
        LogFileGenerator.new(states()).output f
      }
    end

    #
    # Registration
    #

    def add_from_list(target, list)
      if target
        @prev_target = target
      else
        target = @prev_target
      end
      if list.last.kind_of?(UserAction)
        act = list.pop
      else
        act = UserAction.empty
      end
      list.map! {|s| s.kind_of?(UserAction) ? embedded_action(s) : s }
      add Rule.new(target, list, act)
    end

    def embedded_action(act)
      sym = @symboltable.intern("@#{@embedded_action_seq}".intern, true)
      @embedded_action_seq += 1
      add Rule.new(sym, [], act)
      sym
    end
    private :embedded_action

    def add(rule)
      if @close
        raise ArgumentError, "rule added after the Grammar closed"
      end
      @rules.push rule
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
    # On-the-fly generation interface
    #

    def precedence_table(&block)
      env = PrecedenceRegistrationEnv.new(self)
      env.instance_eval(&block)
      end_precedence_declaration env.reverse
    end

    class PrecedenceRegistrationEnv
      def initialize(g)
        @grammar = g
        @prechigh_seen = false
        @preclow_seen = false
        @reverse = false
      end

      attr_reader :reverse

      def prechigh
        if @prechigh_seen
          raise CompileError, "prechigh used twice"
        end
        @prechigh_seen = true
      end

      def preclow
        if @preclow_seen
          raise CompileError, "preclow used twice"
        end
        if @prechigh_seen
          @reverse = true
        end
        @preclow_seen = true
      end

      def left(*syms)
        @grammar.declare_precedence :Left, syms.map {|s| @grammar.intern(s) }
      end

      def right(*syms)
        @grammar.declare_precedence :Right, syms.map {|s| @grammar.intern(s) }
      end

      def nonassoc(*syms)
        @grammar.declare_precedence :Nonassoc, syms.map {|s| @grammar.intern(s)}
      end
    end

    def rule(*symbols, &block)
      Rule.new(nil, symbols.map {|s| intern(s) }, UserAction.proc(block))
    end

    def method_missing(mid, *args, &block)
      unless mid.to_s[-1,1] == '='
        super   # raises NoMethodError
      end
      target = intern(mid.to_s.chop.intern)
      unless args.size == 1
        raise ArgumentError, "too many arguments for #{mid} (#{args.size} for 1)"
      end
      rule = args.first
      rule.target = target
      add rule
      rule.alternatives.each do |r|
        r.target = target
        add r
      end
    end

    #
    # Computation
    #

    def init
      @close = true
      @start ||= @rules.first.target
      raise CompileError, 'no rule in input' if @rules.empty?

      # Adds dummy rule
      r = Rule.new(@symboltable.dummy,
                   [@start, @symboltable.anchor, @symboltable.anchor],
                   UserAction.empty)
      r.ident = 0
      r.hash = 0
      r.precedence = nil
      @rules.unshift r
      @rules.freeze

      # Rule#ident
      # LocationPointer#ident
      @rules.each_with_index do |rule, idx|
        rule.ident = idx
      end

      # Rule#hash
      hashval = 4   # size of dummy rule
      @rules.each do |rule|
        rule.hash = hashval
        hashval += (rule.size + 1)
      end

      # Sym#heads
      @rules.each do |rule|
        rule.target.heads.push rule.ptrs[0]
      end

      # Sym#terminal?, #self_null?
      @symboltable.each do |t|
        t.term = t.heads.empty?
        if t.terminal?
          t.snull = false
          next
        end

        tmp = false
        t.heads.each do |ptr|
          if ptr.reduce?
            tmp = true
            break
          end
        end
        t.snull = tmp
      end

      @symboltable.fix

      # Sym#locate
      @rules.each do |rule|
        t = nil
        rule.ptrs.each do |ptr|
          unless ptr.reduce?
            tok = ptr.dereference
            tok.locate.push ptr
            t = tok if tok.terminal?
          end
        end
        rule.precedence = t
      end

      # Sym#expand
      @symboltable.each_nonterminal {|t| compute_expand t }

      # Sym#nullable?, Rule#nullable?
      compute_nullable

      # Sym#useless?, Rule#useless?
      compute_useless
    end

    def compute_expand(t)
      puts "expand> #{t.to_s}" if @debug_symbol
      t.expand = _compute_expand(t, ISet.new, [])
      puts "expand< #{t.to_s}: #{t.expand.to_s}" if @debug_symbol
    end

    def _compute_expand(t, set, lock)
      if tmp = t.expand
        set.update tmp
        return set
      end
      tok = h = nil
      set.update_a t.heads
      t.heads.each do |ptr|
        tok = ptr.dereference
        if tok and tok.nonterminal?
          unless lock[tok.ident]
            lock[tok.ident] = true
            _compute_expand tok, set, lock
          end
        end
      end
      set
    end

    def compute_nullable
      @rules.each       {|r| r.null = false }
      @symboltable.each {|t| t.null = false }
      r = @rules.dup
      s = @symboltable.nonterminals
      begin
        rs = r.size
        ss = s.size
        check_rules_nullable r
        check_symbols_nullable s
      end until rs == r.size and ss == s.size
    end

    def check_rules_nullable(rules)
      rules.delete_if do |rule|
        rule.null = true
        rule.symbols.each do |t|
          unless t.nullable?
            rule.null = false
            break
          end
        end
        rule.nullable?
      end
    end

    def check_symbols_nullable(symbols)
      symbols.delete_if do |sym|
        sym.heads.each do |ptr|
          if ptr.rule.nullable?
            sym.null = true
            break
          end
        end
        sym.nullable?
      end
    end

    # FIXME: what means "useless"?
    def compute_useless
      @symboltable.each_terminal {|sym| sym.useless = false }
      @symboltable.each_nonterminal {|sym| sym.useless = true }
      @rules.each {|rule| rule.useless = true }
      r = @rules.dup
      s = @symboltable.nonterminals
      begin
        rs = r.size
        ss = s.size
        check_rules_useless r
        check_symbols_useless s
      end until r.size == rs and s.size == ss
    end
    
    def check_rules_useless(rules)
      rules.delete_if do |rule|
        rule.useless = false
        rule.symbols.each do |sym|
          if sym.useless?
            rule.useless = true
            break
          end
        end
        not rule.useless?
      end
    end

    def check_symbols_useless(s)
      t = ptr = nil
      s.delete_if do |t|
        t.heads.each do |ptr|
          unless ptr.rule.useless?
            t.useless = false
            break
          end
        end
        not t.useless?
      end
    end

  end   # class Grammar


  class Rule

    def initialize(target, syms, act)
      @target = target
      @symbols = syms
      @action = act

      @alternatives = []

      @ident = nil
      @hash = nil
      @ptrs = nil
      @precedence = nil
      @specified_prec = nil
      @null = nil
      @useless = nil
    end

    attr_accessor :target
    attr_reader :symbols
    attr_reader :action

    attr_accessor :ident

    attr_reader :hash
    attr_reader :ptrs

    def hash=(n)
      @hash = n
      ptrs = []
      @symbols.each_with_index do |sym, idx|
        ptrs.push LocationPointer.new(self, idx, sym)
      end
      ptrs.push LocationPointer.new(self, @symbols.size, nil)
      @ptrs = ptrs
    end

    attr_reader :precedence
    attr_reader :specified_prec

    def precedence=(sym)
      @precedence ||= sym
    end

    def nullable?() @null end
    def null=(n)    @null = n end

    def useless?()  @useless end
    def useless=(u) @useless = u end

    def |(rule)
      @alternatives.push rule
      self
    end

    attr_reader :alternatives

    def inspect
      "#<Racc::Rule id=#{@ident} (#{@target})>"
    end

    def ==(other)
      other.kind_of?(Rule) and @ident == other.ident
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
      '#<rule#{@ident}>'
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

  end   # class Rule


  class UserAction

    def UserAction.source_text(src)
      new(src, nil)
    end

    def UserAction.proc(pr)
      new(nil, pr)
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

    def proc?
      not @source
    end

    def empty?
      not @proc and not @source
    end

    def name
      "{action type=#{@source || @proc || 'nil'}}"
    end

    alias inspect name

  end


  class OrMark

    def initialize(lineno)
      @lineno = lineno
    end

    def name
      '|'
    end

    alias inspect name

    attr_reader :lineno

  end


  class Prec

    def initialize(tok, lineno)
      @val = tok
      @lineno = lineno
    end

    def name
      '='
    end

    alias inspect name

    attr_reader :val
    attr_reader :lineno

  end


  #
  # A set of rule and position in it's RHS.
  # Note that the number of pointers is more than rule's RHS array,
  # because pointer points right edge of the final symbol when reducing.
  #
  class LocationPointer

    def initialize(rule, i, sym)
      @rule   = rule
      @index  = i
      @symbol = sym
      @ident  = @rule.hash + i
      @reduce = sym.nil?
    end

    attr_reader :rule
    attr_reader :index
    attr_reader :symbol

    alias dereference symbol

    attr_reader :ident
    alias hash ident
    attr_reader :reduce
    alias reduce? reduce

    def to_s
      sprintf('(%d,%d %s)',
              @rule.ident, @index, (reduce?() ? '#' : @symbol.to_s))
    end

    alias inspect to_s

    def eql?(ot)
      @hash == ot.hash
    end

    alias == eql?

    def head?
      @index == 0
    end

    def next
      @rule.ptrs[@index + 1] or ptr_bug!
    end

    alias increment next

    def before(len)
      @rule.ptrs[@index - len] or ptr_bug!
    end

    private
    
    def ptr_bug!
      raise "racc: fatal: pointer not exist: self: #{to_s}"
    end

  end   # class LocationPointer


  class SymbolTable

    include Enumerable

    def initialize
      @symbols = []   # :: [Racc::Sym]
      @cache   = {}   # :: {(String|Symbol) => Racc::Sym}
      @dummy  = intern(:$start, true)
      @anchor = intern(false, true)                   # Symbol ID = 0
      @error  = intern(ErrorSymbolValue.new, false)   # Symbol ID = 1
    end

    attr_reader :dummy
    attr_reader :anchor
    attr_reader :error

    def [](id)
      @symbols[id]
    end

    def intern(val, dummy = false)
      @cache[val] ||=
          begin
            sym = Sym.new(val, dummy)
            @symbols.push sym
            sym
          end
    end

    attr_reader :symbols
    alias to_a symbols

    attr_reader :nt_base

    def nt_max
      @symbols.size
    end

    def each(&block)
      @symbols.each(&block)
    end

    def terminals(&block)
      @symbols[0, @nt_base]
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
      # initialize table
      term = []
      nt = []
      t = i = nil
      @symbols.each do |t|
        (t.terminal? ? term : nt).push t
      end
      @symbols = term + nt
      @nt_base = term.size
      @terms = terminals()
      @nterms = nonterminals()

      @symbols.each_with_index do |t, i|
        t.ident = i
      end

      # check if decleared symbols are really terminal
      if @symbols.any? {|s| s.should_terminal? }
        @anchor.should_terminal
        @error.should_terminal
        terminals().reject {|t| t.should_terminal? }.each do |t|
          raise CompileError, "terminal #{t} not declared as terminal"
        end
        nonterminals().select {|n| n.should_terminal? }.each do |n|
          raise CompileError, "symbol #{n} declared as terminal but is not terminal"
        end
      end
    end

  end   # class SymbolTable


  class ErrorSymbolValue
  end


  # Stands terminal and nonterminal symbols.
  class Sym

    def initialize(value, dummyp)
      @ident = nil
      @value = value
      @dummyp = dummyp

      @term  = nil
      @nterm = nil
      @should_terminal = false
      @precedence = nil
      case value
      when Symbol
        @to_s = value.to_s
        @serialized = value.inspect
      when String
        @to_s = value.inspect
        @serialized = value.dump
      when false
        @to_s = '$end'
        @serialized = 'false'
      when ErrorSymbolValue
        @to_s = 'error'
        @serialized = 'Object.new'
      else
        raise ArgumentError, "unknown symbol value: #{value.class}"
      end

      @heads    = []
      @locate   = []
      @snull    = nil
      @null     = nil
      @expand   = nil
      @useless  = nil
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
      @nterm
    end

    def term=(t)
      raise 'racc: fatal: term= called twice' unless @term.nil?
      @term = t
      @nterm = !t
    end

    def should_terminal
      @should_terminal = true
    end

    def should_terminal?
      @should_terminal
    end

    def serialize
      @serialized
    end

    attr_writer :serialized

    attr_accessor :precedence
    attr_accessor :assoc

    def to_s
      @to_s.dup
    end

    alias inspect to_s

    #
    # cache
    #

    attr_reader :heads
    attr_reader :locate

    def self_null?
      @snull
    end

    once_writer :snull

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

  end   # class Sym

end   # module Racc
