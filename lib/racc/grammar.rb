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
require 'racc/exception'
require 'forwardable'

module Racc

  class UserAction
    def initialize(str, lineno)
      @val = (str.strip.empty? ? nil : str)
      @lineno = lineno
    end

    attr_reader :val
    attr_reader :lineno

    def name
      '{action}'
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


  class Grammar

    def initialize(debug_flags = DebugFlags.new)
      @symboltable = SymbolTable.new
      @debug_symbol = debug_flags.token
      @rules   = []  # :: [Rule]
      @hashval = 4   # size of dummy rule
      @start   = nil
      @sprec   = nil
      @embedded_action_seq = 1
      @n_expected_srconflicts = nil
      @closed = false
    end

    attr_reader :symboltable
    attr_accessor :n_expected_srconflicts

    #
    # Registration
    #

    def add(target, list)
      if target
        @prev_target = target
      else
        target = @prev_target
      end
      if list.last.kind_of?(UserAction)
        act = list.pop
      else
        act = UserAction.new('', 0)
      end
      list.map! {|s| s.kind_of?(UserAction) ? embedded_action(s) : s }
      add0 target, list, act
      @sprec = nil
    end

    def embedded_action(act)
      sym = @symboltable.get("@#{@embedded_action_seq}".intern, true)
      @embedded_action_seq += 1
      add0 sym, [], act
      sym
    end
    private :embedded_action

    def add0(target, list, act)
      @rules.push Rule.new(target, list, act, @rules.size + 1, @hashval, @sprec)
      @hashval += (list.size + 1)
    end
    private :add0

    def start_symbol=(s)
      raise CompileError, "'start' defined twice'" if @start
      @start = s
    end

    #
    # Access
    #

    attr_reader :start

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
      "<Racc::RuleTable>"
    end

    extend Forwardable

    def_delegator "@symboltable", :each, :each_symbol
    def_delegator "@symboltable", :each_terminal
    def_delegator "@symboltable", :each_nonterminal

    def symbols
      @symboltable.to_a
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

    #
    # Computation
    #

    def init
      @close = true
      @start ||= @rules.first.target
      raise CompileError, 'no rule in input' if @rules.empty?

      # add dummy rule
      #
      tmp = Rule.new(@symboltable.dummy,
                     [@start, @symboltable.anchor, @symboltable.anchor],
                     UserAction.new('', 0),
                     0, 0, nil)
                    # id hash prec
      @rules.unshift tmp
      @rules.freeze

      rule = ptr = tmp = tok = t = nil

      # t.heads
      #
      @rules.each do |rule|
        rule.target.heads.push rule.ptrs[0]
      end

      # t.terminal?, self_null?
      #
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

      # t.locate
      #
      @rules.each do |rule|
        tmp = nil
        rule.ptrs.each do |ptr|
          unless ptr.reduce?
            tok = ptr.dereference
            tok.locate.push ptr
            tmp = tok if tok.terminal?
          end
        end
        rule.set_prec tmp
      end

      # t.expand
      #
      @symboltable.each_nonterminal {|t| compute_expand t }

      # t.nullable?, rule.nullable?
      #
      compute_nullable

      # t.useless?, rule.useless?
      #
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
        check_r_nullable r
        check_s_nullable s
      end until rs == r.size and ss == s.size
    end

    def check_r_nullable(r)
      r.delete_if do |rl|
        rl.null = true
        rl.symbols.each do |t|
          unless t.nullable?
            rl.null = false
            break
          end
        end
        rl.nullable?
      end
    end

    def check_s_nullable(s)
      s.delete_if do |t|
        t.heads.each do |ptr|
          if ptr.rule.nullable?
            t.null = true
            break
          end
        end
        t.nullable?
      end
    end

    # FIXME: what means "useless"?
    def compute_useless
      t = del = save = nil

      @symboltable.each_terminal {|t| t.useless = false }
      @symboltable.each_nonterminal {|t| t.useless = true }
      @rules.each {|r| r.useless = true }

      r = @rules.dup
      s = @symboltable.nonterminals
      begin
        rs = r.size
        ss = s.size
        check_r_useless r
        check_s_useless s
      end until r.size == rs and s.size == ss
    end
    
    def check_r_useless(r)
      t = rule = nil
      r.delete_if do |rule|
        rule.useless = false
        rule.symbols.each do |t|
          if t.useless?
            rule.useless = true
            break
          end
        end
        not rule.useless?
      end
    end

    def check_s_useless(s)
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

    def initialize(target, syms, act, rid, hval, prec)
      @target  = target
      @symbols = syms
      @action  = act.val
      @lineno  = act.lineno
      @ident   = rid
      @hash    = hval
      @prec = @specified_prec = prec

      @null    = nil
      @useless = nil

      @ptrs = tmp = []
      syms.each_with_index do |t,i|
        tmp.push LocationPointer.new(self, i, t)
      end
      tmp.push LocationPointer.new(self, syms.size, nil)
    end

    attr_reader :target
    attr_reader :symbols

    attr_reader :action
    attr_reader :lineno

    attr_reader :ident
    attr_reader :hash
    attr_reader :ptrs

    attr_reader :prec
    attr_reader :specified_prec

    def set_prec(t)
      @prec ||= t
    end

    def nullable?() @null end
    def null=(n)    @null = n end

    def useless?()  @useless end
    def useless=(u) @useless = u end

    def inspect
      "#<rule #{@ident} (#{@target})>"
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

  #
  # A set of rule and position in it's rhs.
  # Note that the number of pointers is more than rule's rhs array,
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
      @chk        = {}
      @symbols    = []    # [Sym]
      @token_list = nil
      @prec_table = []

      @end_conv = false
      @end_prec = false
      
      @dummy  = get(:$start, true)
      @anchor = get(:$end,   true)   # Symbol ID = 0
      @error  = get(:error, false)   # Symbol ID = 1

      @anchor.conv = 'false'
      @error.conv = 'Object.new'
    end

    attr_reader :dummy
    attr_reader :anchor
    attr_reader :error

    def get(val, dummy = false)
      unless result = @chk[val]
        @chk[val] = result = Sym.new(val, dummy)
        @symbols.push result
      end
      result
    end

    def declare_terminal(sym)
      (@token_list ||= []).push sym
    end

    def register_prec(assoc, toks)
      raise CompileError, "'prec' block is defined twice" if @end_prec
      toks.push assoc
      @prec_table.push toks
    end

    def end_register_prec(rev)
      @end_prec = true
      return if @prec_table.empty?
      top = @prec_table.size - 1
      @prec_table.each_with_index do |toks, idx|
        ass = toks.pop
        toks.each do |tok|
          tok.assoc = ass
          if rev
            tok.prec = top - idx
          else
            tok.prec = idx
          end
        end
      end
    end

    def register_conv(tok, str)
      if @end_conv
        raise CompileError, "'convert' block is defined twice"
      end
      tok.conv = str
    end

    def end_register_conv
      @end_conv = true
    end

    def fix
      #
      # initialize table
      #
      term = []
      nt = []
      t = i = nil
      @symbols.each do |t|
        (t.terminal? ? term : nt).push t
      end
      @symbols = term + nt
      @nt_base = term.size
      @terms = terminals
      @nterms = nonterminals

      @symbols.each_with_index do |t, i|
        t.ident = i
      end

      return unless @token_list

      #
      # check if decleared symbols are really terminal
      #
      toks = @symbols[2, @nt_base - 2]
      @token_list.uniq!
      @token_list.each do |t|
        unless toks.delete t
          $stderr.puts "racc warning: terminal #{t} decleared but not used"
        end
      end
      toks.each do |t|
        unless t.value.kind_of?(String)
          $stderr.puts "racc warning: terminal #{t} used but not decleared"
        end
      end
    end

    def [](id)
      @symbols[id]
    end

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

  end   # class SymbolTable


  # Stands terminal and nonterminal symbols.
  class Sym

    def initialize(val, dummy)
      @ident = nil
      @value = val
      @dummy = dummy

      @term  = nil
      @nterm = nil
      @conv  = nil
      @prec  = nil

      @heads    = []
      @locate   = []
      @snull    = nil
      @null     = nil
      @expand   = nil

      @useless  = nil

      # for human
      @to_s = if @value.respond_to?(:id2name)
              then @value.id2name
              else @value.to_s.inspect
              end
      # for ruby source
      @uneval = if @value.respond_to?(:id2name)
                then ':' + @value.id2name
                else @value.to_s.inspect
                end
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

    def dummy?() @dummy end

    def terminal?()    @term end
    def nonterminal?() @nterm end

    def term=(t)
      raise 'racc: fatal: term= called twice' unless @term.nil?
      @term = t
      @nterm = !t
    end

    attr_reader :conv

    def conv=(str)
      @conv = @uneval = str
    end

    attr_accessor :prec
    attr_accessor :assoc

    def to_s
      @to_s.dup
    end

    def uneval
      @uneval.dup
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
