#
# grammer.rb
#
#   Copyright (c) 2000 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#
#   This program is free software.
#   You can distribute/modify this program under the terms of
#   the GNU Lesser General Public License version 2 or later.
#

require 'amstd/must'


module Racc

  class UserAction
  
    def initialize( str, lineno )
      @val = (/\A\s*\z/ === str ? nil : str)
      @lineno = lineno
    end

    attr :val
    attr :lineno

    def name
      '{action}'
    end
    alias inspect name
  
  end

  class OrMark

    def initialize( lineno )
      @lineno = lineno
    end

    def name
      '|'
    end
    alias inspect name

    attr :lineno

  end

  class Prec
  
    def initialize( tok, lineno )
      @val = tok
      @lineno = lineno
    end

    def name
      '='
    end
    alias inspect name

    attr :val
    attr :lineno
  
  end


  #########################################################################
  ###########################              ################################
  ###########################     rule     ################################
  ###########################              ################################
  #########################################################################


  #
  # RuleTable
  #
  # stands grammer. Each items of @rules are Rule object.
  #

  class RuleTable

    def initialize( racc )
      @racc        = racc
      @symboltable = racc.symboltable

      @verbose = racc.verbose
      @d_token = racc.d_token
      @d_rule  = racc.d_rule
      @d_state = racc.d_state

      @rules   = []
      @hashval = 4   # size of dummy rule
      @start   = nil
      @sprec   = nil
      @emb     = 1

      @end_rule = false
    end


    ###
    ### register
    ###

    def register_rule_from_array( arr )
      sym = arr.shift
      case sym
      when OrMark, UserAction, Prec
        raise ParseError, "#{sym.lineno}: unexpected token #{sym.name}"
      end
      new = []
      arr.each do |i|
        case i
        when OrMark
          register_rule sym, new
          new = []
        when Prec
          if @sprec then
            raise ParseError, "'=<prec>' used twice in one rule"
          end
          @sprec = i.val
        else
          new.push i
        end
      end
      register_rule sym, new
    end
    
    def register_rule( targ, list )
      if targ then
        @prev_target = targ
      else
        targ = @prev_target
      end

      if UserAction === list[-1] then
        act = list.pop
      else
        act = UserAction.new( '', 0 )
      end
      list.collect! do |t|
        UserAction === t ? embed_symbol(t) : t
      end

      regi targ, list, act
      @start ||= targ
      @sprec = nil
    end

    def regi( targ, list, act )
      tmp = Rule.new( targ, list, act,
                      @rules.size + 1,
                      @hashval, @sprec )
      @rules.push tmp
      @hashval += list.size + 1
    end

    def embed_symbol( act )
      sym = @symboltable.get( "@#{@emb}".intern, true )
      @emb += 1
      regi sym, [], act
      sym
    end

    def end_register_rule
      @end_rule = true
      if @rules.empty? then
        raise RaccError, 'no rule in input'
      end
    end


    def register_start( tok )
      if @start then
        raise ParseError, "'start' defined twice'"
      end
      @start = tok
    end


    def register_option( option )
      if m = /\Ano_/.match(option) then
        opt = m.post_match
        flg = true
      else
        opt = option
        flg = false
      end
      case opt
      when 'omit_action_call'
        @racc.omit_action = inv(flg, true)
      when 'result_var'
        @racc.result_var = inv(flg, true)
      else
        raise ParseError, "unknown option '#{option}'"
      end
    end
    
    def inv( i, f )
      if i then !f else f end
    end


    ###
    ### accessor
    ###

    attr :start

    def []( x )
      @rules[x]
    end

    def each_rule( &block )
      @rules.each( &block )
    end

    alias each each_rule

    def each_index( &block )
      @rules.each_index( &block )
    end

    def each_with_index( &block )
      @rules.each_with_index( &block )
    end

    def size
      @rules.size
    end

    def to_s
      "<Racc::RuleTable>"
    end


    ###
    ### process
    ###

    def init
      $stderr.puts 'initializing values' if @verbose

      #
      # add dummy rule
      #
      tmp = Rule.new( @symboltable.dummy,
                      [ @start, @symboltable.anchor, @symboltable.anchor ],
                      UserAction.new( '', 0 ),
                      0, 0, nil )
                    # id hash prec
      @rules.unshift tmp
      @rules.freeze

      rule = ptr = tmp = tok = t = nil

      #
      # t.heads
      #
      @rules.each do |rule|
        rule.target.heads.push rule.ptrs[0]
      end

      #
      # t.terminal?, self_null?
      #
      @symboltable.each do |t|
        t.term = t.heads.empty?
        tmp = false
        t.heads.each do |ptr|
          if ptr.reduce? then
            tmp = true
            break
          end
        end
        t.snull = tmp
      end

      @symboltable.fix

      #
      # t.locate
      #
      @rules.each do |rule|
        tmp = nil
        rule.ptrs.each do |ptr|
          unless ptr.reduce? then
            tok = ptr.deref
            tok.locate.push ptr
            tmp = tok if tok.terminal?
          end
        end
        rule.set_prec tmp
      end

      #
      # t.expand
      #
      @symboltable.each_nonterm {|t| compute_expand t }

      #
      # t.nullable?
      #
      @symboltable.each_nonterm do |t|
        tmp = false
        t.expand.each do |ptr|
          if tmp = ptr.reduce? then
            break
          end
          if tmp = ptr.deref.self_null? then
            break
          end
        end
        t.null = tmp
      end

      #
      # t.useless?, rule.useless?
      #
      compute_useless

    end


    def compute_expand( t )
      puts "expand> #{t.to_s}" if @d_token
      t.expand = coex( t, ISet.new, [] )
      puts "expand< #{t.to_s}: #{t.expand.to_s}" if @d_token
    end

    def coex( t, ret, lock )
      if tmp = t.expand then
        ret.update tmp
        return ret
      end

      tok = h = nil

      ret.update_a t.heads
      t.heads.each do |ptr|
        tok = ptr.deref
        if tok and tok.nonterminal? then
          unless lock[ tok.ident ] then
            lock[ tok.ident ] = true
            coex( tok, ret, lock )
          end
        end
      end

      ret
    end


    def compute_useless
      del = save = nil

      @symboltable.each_terminal do |t|
        t.useless = false
      end

      r = @rules.dup
      s = @symboltable.nonterminals
      check_r_useless r
      check_s_useless s

      begin
        save = r.size
        check_r_useless r
        check_s_useless s
      end until r.size == save
    end
    
    def check_r_useless( r )
      t = rule = nil
      r.delete_if do |rule|
        rule.useless = false
        unless rule.symbols.empty? then
          rule.symbols.each do |t|
            if t.useless? then
              rule.useless = true
              break
            end
          end
        end
        not rule.useless?
      end
    end

    def check_s_useless( s )
      t = rule = nil
      s.delete_if do |t|
        t.heads.each do |ptr|
          unless ptr.rule.useless? then
            t.useless = false
            break
          end
        end
        not t.useless?
      end
    end

  end   # class RuleTable


  #
  # Rule
  #
  # stands one rule of grammer.
  #

  class Rule

    def initialize( targ, syms, act, rid, hval, prec )
      @target  = targ
      @symbols = syms
      @action  = act.val
      @lineno  = act.lineno
      @ident   = rid
      @hash    = hval
      @useless = true
      @prec = @specified_prec = prec

      @ptrs = tmp = []
      syms.each_with_index do |t,i|
        tmp.push LocationPointer.new( self, i, t )
      end
      tmp.push LocationPointer.new( self, syms.size, nil )
    end

    attr :target
    attr :symbols

    attr :action
    attr :lineno

    attr :ident
    attr :hash
    attr :ptrs

    attr :prec
    attr :specified_prec

    def set_prec( t )
      @prec ||= t
    end

    def useless?()  @useless end
    def useless=(f) @useless = f end

    def inspect
      "#<rule #{@ident} (#{@target})>"
    end

    def ==( other )
      Rule === other and @ident == other.ident
    end

    def []( idx )
      @symbols[idx]
    end

    def size
      @symbols.size
    end

    def to_s
      '#<rule#{@ident}>'
    end

    def accept?
      if tok = @symbols[-1] then
        tok.anchor?
      else
        false
      end
    end

    def each( &block )
      @symbols.each( &block )
    end

  end   # class Rule


  #
  # LocationPointer
  #
  # set of rule and position in it's rhs.
  # note that number of pointer is more than rule's rhs array,
  # because pointer points right of last symbol when reducing.
  #

  class LocationPointer

    def initialize( rule, i, sym )
      @rule   = rule
      @index  = i
      @deref  = sym

      @ident  = @rule.hash + i
      @reduce = sym.nil?
    end

    attr :rule
    attr :index
    attr :deref

    attr :ident;      alias hash      ident
    attr :reduce;     alias reduce?   reduce

    def to_s
      sprintf '(%d,%d %s)',
              @rule.ident, @index, reduce? ? '#' : deref.to_s
    end

    alias inspect to_s

    def eql?( ot )
      @hash == ot.hash
    end

    alias == eql?

    def head?
      @index == 0
    end

    def increment
      @rule.ptrs[ @index + 1 ] or ptr_bug!
    end

    def decrement
      @rule.ptrs[ @index - 1 ] or ptr_bug!
    end

    def before( len )
      @rule.ptrs[ @index - len ] or ptr_bug!
    end

    private
    
    def ptr_bug!
      bug! "pointer not exist: self: #{to_s}"
    end

  end   # class LocationPointer


  #########################################################################
  ###########################              ################################
  ###########################    symbol    ################################
  ###########################              ################################
  #########################################################################

  #
  # SymbolTable
  #
  # the table of symbols.
  # each items of @symbols are Sym
  #

  class SymbolTable

    include Enumerable

    def initialize( racc )
      @chk        = {}
      @symbols    = []
      @token_list = nil
      @prec_table = []

      @end_conv = false
      @end_prec = false
      
      @dummy  = get( :$start, true )
      @anchor = get( :$end,   true )   # ID 0
      @error  = get( :error, false )   # ID 1

      @anchor.conv = 'false'
      @error.conv = 'Object.new'
    end

    attr :dummy
    attr :anchor
    attr :error

    def get( val, dummy = false )
      unless ret = @chk[ val ] then
        @chk[ val ] = ret = Sym.new( val, dummy )
        @symbols.push ret
      end
      ret
    end


    def register_token( toks )
      @token_list ||= []
      @token_list.concat toks
    end


    def register_prec( assoc, toks )
      if @end_prec then
        raise ParseError, "'prec' block is defined twice"
      end
      toks.push assoc
      @prec_table.push toks
    end

    def end_register_prec( rev )
      @end_prec = true

      return if @prec_table.empty?

      top = @prec_table.size - 1
      @prec_table.each_with_index do |toks, idx|
        ass = toks.pop
        toks.each do |tok|
          tok.assoc = ass
          if rev then
            tok.prec = top - idx
          else
            tok.prec = idx
          end
        end
      end
    end


    def register_conv( tok, str )
      if @end_conv then
        raise ParseError, "'convert' block is defined twice"
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
      toks = @symbols[ 2, @nt_base - 2 ]
      @token_list.uniq!
      @token_list.each do |t|
        unless toks.delete t then
          $stderr.puts "racc warning: terminal #{t} decleared but not used"
        end
      end
      toks.each do |t|
        unless String === t.value then
          $stderr.puts "racc warning: terminal #{t} used but not decleared"
        end
      end
    end


    def []( id )
      @symbols[id]
    end

    attr :nt_base

    def nt_max
      @symbols.size
    end

    def each( &block )
      @symbols.each &block
    end

    def terminals( &block )
      @symbols[ 0, @nt_base ]
    end

    def each_terminal( &block )
      @terms.each( &block )
    end

    def nonterminals
      @symbols[ @nt_base, @symbols.size - @nt_base ]
    end

    def each_nonterm( &block )
      @nterms.each( &block )
    end

  end


  #
  # Sym
  #
  # stands symbol (terminal and nonterminal).
  # This class is not named Symbol because there is
  # a class 'Symbol' after ruby 1.5.
  #

  class Sym

    def initialize( val, dummy )
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

      @useless  = true

      # for human
      @to_s =
        if @value.respond_to? 'id2name' then @value.id2name
                                        else @value.to_s.inspect
        end
      # for ruby source
      @uneval =
        if @value.respond_to? 'id2name' then ':' + @value.id2name
                                        else @value.to_s.inspect
        end
    end


    class << self
      def once_writer( nm )
        nm = nm.id2name
        module_eval %-
          def #{nm}=( v )
            bug! unless @#{nm}.nil?
            @#{nm} = v
          end
        -
      end
    end

    #
    # attrs
    #

    once_writer :ident
    attr :ident
    alias hash ident

    attr :value

    def dummy?() @dummy end

    def terminal?()    @term end
    def nonterminal?() @nterm end

    def term=( t )
      bug! unless @term.nil?
      @term = t
      @nterm = !t
    end

    def conv=( str ) @conv = @uneval = str end
    attr :conv

    attr_accessor :prec
    attr_accessor :assoc

    def to_s()   @to_s.dup end
    def uneval() @uneval.dup end
    alias inspect to_s

    #
    # computed
    #

    attr :heads
    attr :locate

    once_writer :snull
    def self_null?() @snull end

    once_writer :null
    def nullable?() @null end

    once_writer :expand
    attr :expand

    def useless=(f) @useless = f end
    def useless?() @useless end

  end   # class Sym

end   # module Racc
