#
# state.rb
#
#   Copyright (c) 1999,2000 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#
#   This program is free software.
#   You can distribute/modify this program under the terms of
#   the GNU Lesser General Public License version 2 or later.
#

require 'amstd/must'


module Racc

  class RaccError < StandardError; end


  class ISet

    def initialize( a = [] )
      @set = a
    end

    attr :set

    def add( i )
      @set[ i.ident ] = i
    end

    def []( key )
      @set[ key.ident ]
    end

    def []=( key, val )
      @set[ key.ident ] = val
    end

    alias include? []
    alias key? []

    def update( other )
      s = @set; o = other.set
      i = t = nil
      o.each_index {|i| if t = o[i] then s[i] = t end }
    end

    def update_a( a )
      s = @set
      i = nil
      a.each {|i| s[ i.ident ] = i }
    end

    def delete( key )
      i = @set[ key.ident ]
      @set[ key.ident ] = nil
      i
    end

    def each( &block )
      @set.compact.each( &block )
    end

    def to_a
      @set.compact
    end

    def to_s
      "[#{@set.compact.join(' ')}]"
    end
    alias inspect to_s

    def size
      @set.nitems
    end

    def empty?
      @set.nitems == 0
    end

    def clear
      @set.clear
    end

    def dup
      ISet.new @set.dup
    end
  
  end


  #######################################################################
  ###########################            ################################
  ###########################    rule    ################################
  ###########################            ################################
  #######################################################################


  class RuleTable

    def initialize( racc )
      @racc = racc
      @tokentable = racc.tokentable

      @d_token = racc.d_token
      @d_rule  = racc.d_rule
      @d_state = racc.d_state
      @verbose = racc.d_verbose

      @rules    = []
      @finished = false
      @hashval  = 4
      @start    = nil
    end


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


    def register( sym, rulearr, tempprec, act )
      rule = Rule.new(
        sym, rulearr, act,
        @rules.size + 1,         # ID
        @hashval,                # hash value
        tempprec                 # prec
      )
      @rules.push rule

      @hashval += rulearr.size + 2
    end

    def start=( sim )
      unless @start then
        @start = sim
        true
      else
        false
      end
    end
    
    attr :start


    def init
      $stderr.puts 'initializing values' if @verbose

      #
      # add dummy rule
      #
      tmp = Rule.new(
          @tokentable.dummy,
          [ @start, @tokentable.anchor, @tokentable.anchor ],
          Action.new( '', 0 ),
          0, 0, nil )
        # id hash prec
      @rules.unshift tmp
      @rules.freeze

      ###
      ### cache
      ###

      rule = ptr = orig = tmp = tok = t = s = nil

      #
      # t.heads
      #
      @rules.each do |rule|
        rule.symbol.heads.push rule.ptrs[0]
      end

      #
      # t.terminal?, self_null?
      #
      @tokentable.each do |t|
        t.term = (t.heads.size == 0)
        tmp = false
        t.heads.each do |ptr|
          if ptr.reduce? then
            tmp = true
            break
          end
        end
        t.snull = tmp
      end

      @tokentable.fix

      #
      # t.nt_heads, locate, rule.prec
      #
      @rules.each do |rule|
        ptr = rule.ptrs[0]
        t = ptr.unref
        if t then
          if t.nonterminal? then
            rule.symbol.nt_heads.push ptr
          end
        else
          rule.symbol.void_heads.push ptr
        end

        tmp = nil
        rule.ptrs.each do |ptr|
          unless ptr.reduce? then
            tok = ptr.unref
            tok.locate.push ptr
            tmp = tok if tok.term
          end
        end
        rule.prec ||= tmp
      end

      #
      # t.expand
      #
      @tokentable.each_nonterm {|t| compute_expand t }

      #
      # t.nullable?
      #
      @tokentable.each_nonterm do |t|
        tmp = false
        t.expand.each do |ptr|
          if tmp = ptr.reduce? then
            break
          end
          if tmp = ptr.unref.self_null? then
            break
          end
        end
        t.null = tmp
      end

      #
      # nt.first_terms
      #
      s = nil
      @tokentable.each_nonterm do |tok|
        s = ISet.new
        tok.expand.each do |ptr|
          t = ptr.unref
          if t and t.terminal? then
            s.add ptr
          end
        end
        tok.first_terms = s.to_a
      end

      @tokentable.each_nonterm {|t| compute_first t }
      @tokentable.each_nonterm {|t| compute_void_reduce t }

      #
      # pointer.null?
      #
      @rules.each do |rule|
        rule.ptrs.each do |ptr|
          s = ptr.first
          orig = ptr
          until ptr.reduce? do
            t = ptr.unref
            if t.terminal? then
              s.add t
              orig.null = false
              break
            else
              s.update t.first
              unless t.nullable? then
                orig.null = false
                break
              end
            end
            ptr = ptr.increment
          end
        end
      end

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
      t.nt_heads.each do |ptr|
        tok = ptr.unref
        unless lock[ tok.ident ] then
          lock[ tok.ident ] = true
          coex( tok, ret, lock )
        end
      end

      ret
    end


    def compute_void_reduce( t )
      if t.nullable? then
        a = [ t, @tokentable.uniq_token ]
        all = []
        cvor( a, all, [] )
        all.collect! do |a|
          ptr = a.pop
          LALRitem.new( ptr, first(a) )
        end
        t.void_reduce = all
      end
    end

    def cvor( a, all, lock )
      ptr = lo = nil

      t = a.shift
      t.nt_heads.each do |ptr|
        if ptr.unref.nullable? then
          next if lock[ ptr.ident ]

          a = a.dup; a[0,0] = ptr.follow_tokens
          lo = lock.dup; lo[ ptr.ident ] = ptr
          cvor( a, all, lo )
        end
      end
      t.void_heads.each do |ptr|
        a = a.dup
        a.push ptr
        all.push a
      end
    end

    def first( arr )
      s = ISet.new
      t = nil
      arr.each do |t|
        if t.terminal? then
          s.add t
          break
        else
          s.update t.first
          break unless t.nullable?
        end
      end

      s
    end


    def compute_first( t )
      puts "first> #{to_s}" if @d_token
      t.first = cfir( t, ISet.new, [] )
      puts "first< #{to_s}: #{t.first.to_s}" if @d_token
    end

    def cfir( t, ret, lock )
      if tmp = t.first then
        ret.update tmp
        return ret
      end
      lock[t.ident] = t

      ptr = tok = nil

      if t.terminal? then
        bug! '"first" called for terminal'
      else
        t.heads.each do |ptr|
          until ptr.reduce? do
            tok = ptr.unref
            if tok.terminal? then
              ret.add tok
              break
            else
              cfir( tok, ret, lock ) unless lock[tok.ident]
              break unless tok.nullable?
            end

            ptr = ptr.increment
          end
        end
      end

      ret
    end

  end   # RuleTable


  #######################################################################
  #######################################################################


  class Rule

    def initialize( tok, rlarr, act, rid, hval, tprec )
      @symbol  = tok
      @rulearr = rlarr
      @action  = act.val
      @lineno  = act.lineno
      @ident   = rid
      @hash    = hval
      @prec    = tprec
      @useless = false

      @ptrs = a = []
      rlarr.each_with_index do |t,i|
        a.push LocationPointer.new( self, i, t )
      end
      a.push LocationPointer.new( self, rlarr.size, nil )
    end


    attr :symbol; alias simbol symbol
    attr :action
    attr :lineno
    attr :ident;  alias ruleid ident
    attr :hash
    attr :prec, true
    attr :ptrs

    def ==( other )
      Rule === other and @ident == other.ident
    end

    def accept?()
      if tok = @rulearr[-1] then
        tok.anchor?
      else
        false
      end
    end

    def []( idx )
      @rulearr[idx]
    end

    def size
      @rulearr.size
    end

    def to_s
      '#<rule#{@ident}>'
    end

    def toks
      @rulearr
    end

    def tokens
      @rulearr.dup
    end

    def useless=( f )
      if @useless then
        bug! 'rule.useless was set twice'
      end
      @useless = f
    end

    def useless?
      @useless
    end

    def each_token( &block )
      @rulearr.each( &block )
    end
    alias each each_token

    def each_with_index( &block )
      @rulearr.each_with_index( &block )
    end

  end   # Rule


  #######################################################################
  #######################################################################


  class LocationPointer

    def initialize( rl, idx, tok )
      @rule   = rl
      @index  = idx
      @unref  = tok

      @ident  = @rule.hash + @index
      @reduce = tok.nil?
      @null   = true
      @first  = ISet.new
    end


    attr :rule
    attr :index
    attr :unref

    attr :ident;      alias hash      ident
    attr :reduce;     alias reduce?   reduce
    attr :null, true; alias nullable? null
    attr :first


    def to_s
      sprintf( '(%d,%d %s)',
               @rule.ident, @index, reduce? ? '#' : unref.to_s )
    end
    alias inspect to_s

    def eql?( ot )
      @hash == ot.hash
    end
    alias == eql?

    def follow_tokens
      a = @rule.toks
      a[ @index, a.size - @index ]
    end

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


  ########################################################################
  ###########################             ################################
  ###########################    token    ################################
  ###########################             ################################
  ########################################################################


  class TokenTable

    include Enumerable

    def initialize( racc )
      @racc = racc

      @chk = {}
      @tokens = []
      
      @dummy   = get( :$start )
      @anchor  = get( :$end )
      @error   = get( :error )   # error token is ID 1

      @anchor.conv = 'false'
      @error.conv = 'Object.new'
    end

    attr :dummy
    attr :anchor
    attr :uniq_token

    def get( val )
      unless ret = @chk[ val ] then
        @chk[ val ] = ret = Token.new( val, @racc )
        @tokens.push ret
      end

      ret
    end

    def fix
      term = []
      nt = []
      t = i = nil
      @tokens.each do |t|
        (t.terminal? ? term : nt).push t
      end
      @tokens = term
      @nt_base = term.size
      term.concat nt

      @tokens.each_with_index do |t, i|
        t.ident = i
      end

      @uniq_token = Token.new( :$uniq, @racc )
      @uniq_token.ident = @tokens.size
      @uniq_token.term = true
    end

    def []( id )
      @tokens[id]
    end

    attr :nt_base

    def nt_max
      @tokens.size
    end

    def each( &block )
      @tokens.each &block
    end

    def each_terminal( &block )
      @tokens[ 0, @nt_base ].each( &block )
    end

    def each_nonterm( &block )
      @tokens[ @nt_base, @tokens.size - @nt_base ].each( &block )
    end

  end   # TokenTable


  class Token

    Default_token_id = -1
    Anchor_token_id  = 0
    Error_token_id   = 1

    def initialize( tok, racc )
      @ident   = nil
      @value   = tok

      @term   = nil
      @nterm  = nil
      @conv   = nil

      @heads       = []
      @nt_heads    = []
      @void_heads  = []
      @locate      = []
      @snull       = nil
      @null        = nil
      @expand      = nil
      @void_reduce = nil
      @first_terms = nil
      @first       = nil

      @useless     = nil

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

    attr :ident; once_writer :ident
    alias tokenid ident
    alias hash ident

    attr :value

    attr :term
    attr :nterm
    attr :conv # true
    attr :prec,  true
    attr :assoc, true

    alias terminal? term
    alias nonterminal? nterm

    def term=( t )
      bug! unless @term.nil?
      @term = t
      @nterm = !t
    end

    def conv=( str )
      @conv = @uneval = str
    end

    attr :heads
    attr :nt_heads
    attr :void_heads
    attr :locate
    attr :snull; once_writer :snull
    attr :null;  once_writer :null

    alias self_null? snull
    alias nullable? null

    attr :expand;      once_writer :expand
    attr :void_reduce; once_writer :void_reduce
    attr :first_terms; once_writer :first_terms
    attr :first;       once_writer :first

    def to_s
      @to_s.dup
    end
    alias inspect to_s

    def uneval
      @uneval.dup
    end


    once_writer :useless

    def useless?
      @useless
    end

  end   # class Token



  ########################################################################
  ###########################             ################################
  ###########################    state    ################################
  ###########################             ################################
  ########################################################################


  class LALRstateTable

    def initialize( racc )
      @racc = racc
      @ruletable  = racc.ruletable
      @tokentable = racc.tokentable
      @anchor_t   = racc.tokentable.anchor

      @d_state  = racc.d_state
      @d_reduce = racc.d_reduce
      @d_shift  = racc.d_shift
      @verbose  = racc.d_verbose
      @prof     = racc.d_profile

      @states = []
      @statecache = {}

      @actions = LALRactionTable.new( @ruletable, self )
    end

    attr :actions

    def size
      @states.size
    end

    def inspect
      '#<state table>'
    end
    alias to_s inspect

    def []( i )
      @states[i]
    end

    def each_state( &block )
      @states.each( &block )
    end
    alias each each_state

    def each_index( &block )
      @states.each_index( &block )
    end


    ###
    ### nfa
    ###

    def init
      $stderr.puts 'generating states' if @verbose

      # add state 0
      core_to_state( [ @ruletable[0].ptrs[0] ] )

      cur = 0
      while cur < @states.size do
        develop_state @states[cur]   # state is added here
        cur += 1
      end

      @actions.init
    end

    def develop_state( state )
      puts "dstate: #{state}" if @d_state

      table = {}
      s = ptr = pt = nil

      state.core.each do |ptr|
        if tok = ptr.unref then
          add_tok_ptr table, tok, ptr.increment
          if tok.nonterminal? then
            tok.expand.each do |pt|
              add_tok_ptr table, pt.unref, pt.increment unless pt.reduce?
            end
          end
        end
      end

      table.each do |tok,core|
        puts "dstate: tok=#{tok} ncore=#{core}" if @d_state

        dest = core_to_state( core.to_a )
        state.goto_table[ tok ] = dest
        puts "dstate: #{state.ident} --(#{tok})-> #{dest.ident}" if @d_state

        # check infinite recursion
        if state.ident == dest.ident and state.core.size == 1 and
           state.items[0].ptr.unref.expand.size == 1 then
          raise RaccError,
            sprintf( "Infinite recursion: state %d, with rule %d",
                     state.ident, state.ptrs[0].rule.ident )
        end
      end
    end

    def add_tok_ptr( table, tok, ptr )
      unless s = table[tok] then
        table[tok] = s = ISet.new
      end
      s.add ptr
    end

    def core_to_state( core )
      k = fingerprint( core )
      unless dest = @statecache[k] then
        # not registered yet
        dest = LALRstate.new( @states.size, core, @racc )
        @states.push dest

        @statecache[k] = dest
        
        puts "core_to_state: create state   ID #{dest.ident}" if @d_state
      else
        if @d_state then
          puts "core_to_state: dest is cached ID #{dest.ident}"
          puts "core_to_state: dest core #{dest.core.join(' ')}"
        end
      end

      dest
    end

    def fingerprint( arr )
      arr.collect {|i| i.ident }.pack( 'L*' )
    end


    ###
    ### dfa
    ###

    def resolve
      $stderr.puts "resolving #{@states.size} states" if @verbose

      state = item = nil
      b = Time.times.utime
      i = 0

      # step 2
      $stderr.print 'generating internal      ' if @verbose
      @states.each do |state|
        if @verbose then
          $stderr.printf "\b\b\b\b\b%-5d", state.ident
          $stderr.flush
        end
        state.generate_intern
      end
      $stderr.puts "\ninit trans" if @verbose
      @states.each do |state|
        state.items.each do |item|
          unless item.trans_items.empty? then
            item.init
          end
        end
      end

      # step 3
      $stderr.puts "updating new la-tokens" if @verbose
      added = true
      while added do
        i += 1
        $stderr.puts "loop \##{i}" if @verbose

        added = false
        @states.each do |state|
          state.items.each {|item| item.trans }
        end
        @states.each do |state|
          state.items.each do |item|
            f = item.next_turn
            added ||= f
          end
        end
      end

      # step 4
      @states.each do |state|
        state.determine
      end

      if @verbose then
        e = Time.times.utime
        $stderr.puts "all resolved in #{e - b} sec, #{i} times loop"
      end

      set_accept
      pack_states
      check_useless
    end

    def set_accept
      anch = @anchor_t
      init_state = @states[0].goto_table[ @ruletable.start ]
      targ_state = init_state.action[ anch ].goto_state
      acc_state  = targ_state.action[ anch ].goto_state

      acc_state.action.clear
      acc_state.goto_table.clear
      acc_state.defact = @actions.accept
    end


    def pack_states
      st = arr = act = nil
      i = n = s = r = nil

      @states.each do |st|
        #
        # find most frequently used reduce rule
        #
        act = st.action
        arr = Array.new( @ruletable.size, 0 )
        act.each do |t,a|
          if ReduceAction === a then
            arr[ a.ruleid ] += 1
          end
        end
        i = s = nil
        i = arr.max
        s = arr.index( i ) if i > 0

        if s then
          r = @actions.reduce(s)
          if not st.defact or st.defact == r then
            act.delete_if {|t,a| a == r }
            st.defact = r
          end
        else
          st.defact ||= @actions.error
        end
      end
    end


    def check_useless
      act = nil
      used = []
      @actions.each_reduce do |act|
        if not act or act.refn == 0 then
          act.rule.useless = true
        else
          t = act.rule.symbol
          used[ t.ident ] = t
        end
      end
      @tokentable.nt_base.upto( @tokentable.nt_max - 1 ) do |n|
        unless used[n] then
          @tokentable[n].useless = true
        end
      end
    end

  end   # LALRstateTable


  ########################################################################
  ########################################################################


  class LALRitem
  
    def initialize( ptr, la = ISet.new )
      @ptr = ptr
      @ident = ptr.ident
      @trans_items = nil
      @la     = la
      @newla  = []
      @curr_t = []
    end

    attr :ptr
    attr :ident
    attr :trans_items, true
    attr :la
    # attr :curr_t
    # attr :newla

    def to_s
      "#<LALRitem #{@ptr}>"
    end
    alias inspect to_s

    def dup
      LALRitem.new( @ptr, @la.dup )
    end


    def init
      curr = @curr_t
      i = nil
      @la.set.each do |i|
        curr[ i.ident ] = i if i
      end
      curr.compact!
    end

    def trans
      unless (curr = @curr_t).empty? then
        @trans_items.each do |ti|
          ti.add_new_la curr
        end
      end
    end

    def add_new_la( arr )
      la = @la.set
      nl = @newla
      t = ti = nil
      arr.each do |t|
        unless la[ ti = t.ident ] then
          la[ti] = nl[ti] = t
        end
      end
    end
    protected :add_new_la

    def next_turn
      (new = @curr_t).clear
      (cur = @newla).compact!
      @curr_t = cur
      @newla  = new

      not cur.empty?
    end

  end


  ########################################################################
  ########################################################################


  class LALRstate

    def initialize( ident, core, racc )
      @ident = ident
      @core = core

      @racc       = racc
      @uniq_t     = racc.tokentable.uniq_token
      @actions    = racc.statetable.actions
      @d_state    = racc.d_state
      @d_reduce   = racc.d_reduce
      @d_shift    = racc.d_shift
      @verbose    = racc.d_verbose
      @prof       = racc.d_profile

      @goto_table = {}

      @action = {}
      @defact = nil

      @resolve_log = []

      @rrconf = nil
      @srconf = nil

      #---

      ptr = nil
      @ptr_to_item = s = ISet.new
      @core.each {|ptr| s[ ptr ] = LALRitem.new( ptr ) }
      @items = s.to_a
    end


    attr :ident
    alias stateid ident
    alias hash ident

    attr :core
    attr :items
    attr :ptr_to_item

    attr :goto_table

    attr :action
    attr :defact, true   # default action

    attr :resolve_log

    attr :rrconf
    attr :srconf

    def inspect
      "#<LALRstate #{@ident}>"
    end
    alias to_s inspect

    def ==( oth )
      @ident == oth.ident
    end

    alias eql? ==


    def generate_intern
      i = item = transi = nil
      uniq = @uniq_t
      tran = []

      @items.each do |item|
        closure( item.ptr ).each do |i|
          unless i.ptr.reduce? then
            transi = @goto_table[i.ptr.unref].ptr_to_item[i.ptr.increment]
            if i.la.delete uniq then
              tran[ transi.ptr.ident ] = transi
            end
            transi.la.update(i.la) unless i.la.empty?
          end
        end

        item.trans_items = tran.compact
        tran.clear
      end
    end

    def closure( ip )
      #
      # init
      #
      clo = ISet.new
      clo[ ip ] = i = LALRitem.new( ip )
      i.la.add @uniq_t
      t = ip.unref
      if t and t.nonterminal? then
        t.expand.each do |ptr|
          clo[ ptr ] = LALRitem.new( ptr )
        end
      end

      clo_a = clo.to_a

      return clo if ip.reduce?

      i = tmp = np = nil

      #
      # generate intern
      #
      tran = []
      clo_a.each do |i|
        t = i.ptr.unref
        if t and t.nonterminal? then
          np = i.ptr.increment
          t.heads.each do |ptr|
            clo[ptr].la.update np.first
            if np.nullable? then
              tran[ptr.ident] = clo[ptr]
            end
          end
        end
        i.trans_items = tran.compact
        tran.clear
      end
      clo_a.each do |i|
        i.init unless i.trans_items.empty?
      end

      #
      # trans
      #
# stt = Time.times.utime
# puts clo_a.size
      continu = true
# idx = 0
      while continu do
# idx += 1
        continu = false
        clo_a.each {|i| i.trans }
        clo_a.each do |i|
          f = i.next_turn
          continu ||= f
        end
      end
# puts "#{idx} times loop, #{Time.times.utime - stt} sec"

      clo
    end


    def determine
      r = reduce_items
      s = shift_toks
      tok = nil

      if r.empty? then
        # shift
        s.each do |tok|
          @action[ tok ] = @actions.shift( @goto_table[tok] )
        end
      else
        if r.size == 1 and s.empty? then
          # reduce
          @defact = @actions.reduce( r.to_a[0].ptr.rule )
        else
          # conflict
          resolve_rr r
          resolve_sr s
        end
      end
    end

    def reduce_items
      r = ISet.new
      uniq = @uniq_t
      ptr = item = i = a = nil

      @items.each do |item|
        ptr = item.ptr
        if ptr.reduce? then
          r.add item
        else
          if a = ptr.unref.void_reduce then   # nonterminal
            a.each do |i|
              i = i.dup
              if i.la.delete uniq then
                i.la.update ptr.increment.first
                if ptr.increment.nullable? then
                  i.la.update item.la
                end
              end
#puts "state #{@ident}, void_reduce ptr=#{i.ptr}"
#puts "LA=#{i.la}"
              r.add i
            end
          end
        end
      end

      r.to_a
    end

    def shift_toks
      s = ISet.new
      @goto_table.each_key do |t|
        s.add t if t.terminal?
      end
      s.to_a
    end


    def resolve_rr( r )
      pt = tok = act = item = nil

      r.each do |item|
        item.la.each do |tok|
          act = @action[ tok ]
          if act then
            bug! "#{act.type} in action table" unless ReduceAction === act
            #
            # can't resolve R/R conflict (on tok).
            #   reduce with upper rule as default
            #
            rr_conflict act.rule, item.ptr.rule, tok
          else
            # not conflict
            @action[ tok ] = @actions.reduce( item.ptr.rule )
          end
        end
      end
    end

    def resolve_sr( s )
      stok = rtok = goto = act = nil

      s.each do |stok|
        goto = @goto_table[stok]
        act = @action[stok]

        unless act then
          # no conflict
          @action[ stok ] = @actions.shift( goto )
        else
          bug! "#{act.type} in action table" unless ReduceAction === act

          # conflict on stok

          rtok = act.rule.prec
          case do_resolve_sr( stok, rtok )
          when :Reduce        # action is already set

          when :Shift         # overwrite
            act.decref
            @action[ stok ] = @actions.shift( goto )

          when :Remove        # remove
            act.decref
            @action.delete stok

          when :CantResolve   # shift as default
            act.decref
            @action[ stok ] = @actions.shift( goto )
            sr_conflict stok, act.rule
          end
        end
      end
    end
    
    def do_resolve_sr( stok, rtok )
      puts "resolve_sr: s/r conflict: rtok=#{rtok}, stok=#{stok}" if @d_shift

      unless rtok and rtok.prec then
        puts "resolve_sr: no prec for #{rtok}(R)" if @d_shift
        return :CantResolve
      end
      rprec = rtok.prec

      unless stok and stok.prec then
        puts "resolve_sr: no prec for #{stok}(S)" if @d_shift
        return :CantResolve
      end
      sprec = stok.prec

      ret = if rprec == sprec then
              case rtok.assoc
              when :Left     then :Reduce
              when :Right    then :Shift
              when :Nonassoc then :Remove  # 'rtok' makes error
              else
                bug! "#{rtok}.assoc is not Left/Right/Nonassoc"
              end
            else
              if rprec > sprec
              then :Reduce
              else :Shift
              end
            end

      puts "resolve_sr: resolved as #{ret.id2name}" if @d_shift
      ret
    end
    private :do_resolve_sr


    def rr_conflict( high, low, ctok )
      c = RRconflict.new( @ident, high, low, ctok )

      unless @rrconf then
        @rrconf = {}
      end
      if a = @rrconf[ctok] then
        a.push c
      else
        @rrconf[ctok] = [c]
      end
    end

    def sr_conflict( shift, reduce )
      c = SRconflict.new( @ident, shift, reduce )

      unless @srconf then
        @srconf = {}
      end
      if a = @srconf[shift] then
        a.push c
      else
        @srconf[shift] = [c]
      end
    end

  end   # LALRstate



  class LALRactionTable

    def initialize( rt, st )
      @ruletable = rt
      @statetable = st

      @reduce = []
      @shift = []
      @accept = nil
      @error = nil
    end

    def init
      @ruletable.each do |rl|
        @reduce.push ReduceAction.new( rl )
      end
      @statetable.each do |st|
        @shift.push ShiftAction.new( st )
      end
      @accept = AcceptAction.new
      @error = ErrorAction.new
    end


    def reduce_n
      @reduce.size
    end

    def reduce( i )
      if Rule === i then
        i = i.ident
      else
        i.must Integer
      end

      unless ret = @reduce[i] then
        bug! "reduce action #{i} not exist"
      end
      ret.incref
      ret
    end

    def each_reduce( &block )
      @reduce.each &block
    end


    def shift_n
      @shift.size
    end

    def shift( i )
      if LALRstate === i then
        i = i.ident
      else
        i.must Integer
      end

      @shift[i] or bug! "shift action #{i} not exist"
    end

    def each_shift( &block )
      @shift.each &block
    end


    attr :accept
    attr :error

  end


  class LALRaction
  end


  class ShiftAction < LALRaction

    def initialize( goto )
      @goto_state = goto
    end

    attr :goto_state

    def goto_id
      @goto_state.ident
    end

    def inspect
      "<shift #{@goto_state.ident}>"
    end

  end


  class ReduceAction < LALRaction

    def initialize( rule )
      @rule = rule
      @refn = 0
    end

    attr :rule
    attr :refn

    def ruleid
      @rule.ident
    end

    def inspect
      "<reduce #{@rule.ident}>"
    end

    def incref
      @refn += 1
    end

    def decref
      @refn -= 1
      if @refn < 0 then
        bug! 'act.refn < 0'
      end
    end

  end


  class AcceptAction < LALRaction

    def inspect
      "<accept>"
    end

  end


  class ErrorAction < LALRaction

    def inspect
      "<error>"
    end
  
  end


  class ConflictData ; end

  class SRconflict < ConflictData

    def initialize( sid, shift, reduce )
      @stateid = sid
      @shift   = shift
      @reduce  = reduce
    end
    
    attr :stateid
    attr :shift
    attr :reduce
  
    def to_s
      sprintf( 'state %d: S/R conflict rule %d reduce and shift %s',
               @stateid, @reduce.ruleid, @shift.to_s )
    end

  end

  class RRconflict < ConflictData
    
    def initialize( sid, high, low, tok )
      @stateid   = sid
      @high_prec = high
      @low_prec  = low
      @token     = tok
    end

    attr :stateid
    attr :high_prec
    attr :low_prec
    attr :token
  
    def to_s
      sprintf( 'state %d: R/R conflict with rule %d and %d on %s',
               @stateid, @high_prec.ident, @low_prec.ident, @token.to_s )
    end

  end

end   # module Racc
