#
# state.rb
#
#   Copyright (c) 1999-2001 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#
#   This program is free software.
#   You can distribute/modify this program under the terms of
#   the GNU Lesser General Public License version 2 or later.
#

require 'racc/iset'
require 'amstd/must'


module Racc

  class RaccError < StandardError; end


  #
  # StateTable
  #
  # the table of lalr states.
  #

  class StateTable

    def initialize( racc )
      @ruletable   = racc.ruletable
      @symboltable = racc.symboltable

      @d_state = racc.d_state
      @d_la    = racc.d_la
      @d_prec  = racc.d_prec

      @states = []
      @statecache = {}

      @actions = ActionTable.new( @ruletable, self )
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
      # add state 0
      core_to_state( [ @ruletable[0].ptrs[0] ] )

      cur = 0
      @gotos = []
      while cur < @states.size do
        generate_states @states[cur]   # state is added here
        cur += 1
      end

      @actions.init
    end

    def generate_states( state )
      puts "dstate: #{state}" if @d_state

      table = {}
      ptr = pt = s = g = nil

      state.closure.each do |ptr|
        if sym = ptr.deref then
          addsym table, sym, ptr.next
        end
      end

      table.each do |sym, core|
        puts "dstate: sym=#{sym} ncore=#{core}" if @d_state

        dest = core_to_state( core.to_a )
        state.goto_table[sym] = dest
        id = if sym.nonterminal? then @gotos.size else nil end
        g = Goto.new( id, sym, state, dest )
        if sym.nonterminal? then
          @gotos.push g
        end
        state.gotos[sym] = g
        puts "dstate: #{state.ident} --#{sym}--> #{dest.ident}" if @d_state

        # check infinite recursion
        if state.ident == dest.ident and state.closure.size == 1 then
          raise RaccError,
            sprintf( "Infinite recursion: state %d, with rule %d",
                     state.ident, state.ptrs[0].rule.ident )
        end
      end
    end

    def addsym( table, sym, ptr )
      unless s = table[sym] then
        table[sym] = s = ISet.new
      end
      s.add ptr
    end

    def core_to_state( core )
      #
      # creates/find state keeping core unique
      #

      k = fingerprint( core )
      unless dest = @statecache[k] then
        # not registered yet
        dest = State.new( @states.size, core )
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

    def determine
      la = lookahead
      @states.each do |state|
        state.set_la la
        resolve state
      end

      set_accept
      @states.each do |state|
        pack state
      end
      check_useless
    end


    #
    # lookahead
    #

    def lookahead
      #
      # lookahead algorithm ver.3 -- from bison 1.26
      #
      state = goto = arr = ptr = st = rl = i = a = t = g = nil

      gotos = @gotos
      if @d_la then
        puts "\n--- goto ---"
        gotos.each_with_index {|g,i| print i, ' '; p g }
      end

      ### initialize_LA()
      ### set_goto_map()
      la_rules = []
      @states.each do |state|
        state.check_la( la_rules )
      end


      ### initialize_F()
      f     = create_tmap( gotos.size )
      reads = []
      edge  = []
      gotos.each do |goto|
        goto.to_state.goto_table.each do |t, st|
          if t.terminal? then
            f[goto.ident] |= (1 << t.ident)
          elsif t.nullable? then
            edge.push goto.to_state.gotos[t].ident
          end
        end
        if edge.empty? then
          reads.push nil
        else
          reads.push edge
          edge = []
        end
      end
      digraph f, reads
      if @d_la then
        puts "\n--- F1 (reads) ---"
        print_tab gotos, reads, f
      end


      ### build_relations()
      ### compute_FOLLOWS
      path = nil
      edge = []
      lookback = Array.new( la_rules.size, nil )
      includes = []
      gotos.each do |goto|
        goto.symbol.heads.each do |ptr|
          path = record_path( goto.from_state, ptr.rule )
          g = path[-1]
          st = g ? g.to_state : goto.from_state
          if st.conflict? then
            addrel lookback, st.rruleid(ptr.rule), goto
          end
          path.reverse_each do |g|
            break if     g.symbol.terminal?
            edge.push    g.ident
            break unless g.symbol.nullable?
          end
        end
        if edge.empty? then
          includes.push nil
        else
          includes.push edge
          edge = []
        end
      end
      includes = transpose( includes )
      digraph f, includes
      if @d_la then
        puts "\n--- F2 (includes) ---"
        print_tab gotos, includes, f
      end


      ### compute_lookaheads
      la = create_tmap( la_rules.size )
      lookback.each_with_index do |arr, i|
        if arr then
          arr.each do |g|
            la[i] |= f[g.ident]
          end
        end
      end
      if @d_la then
        puts "\n--- LA (lookback) ---"
        print_tab la_rules, lookback, la
      end

      la
    end
    
    def create_tmap( siz )
      Array.new( siz, 0 )   # use Integer as bitmap
    end

    def addrel( tbl, i, item )
      if a = tbl[i] then
        a.push item
      else
        tbl[i] = [item]
      end
    end

    def record_path( begst, rule )
      st = begst
      path = []
      rule.symbols.each do |t|
        goto = st.gotos[t]
        path.push goto
        st = goto.to_state
      end
      path
    end

    def transpose( rel )
      new = Array.new( rel.size, nil )
      rel.each_with_index do |arr, idx|
        if arr then
          arr.each do |i|
            addrel new, i, idx
          end
        end
      end
      new
    end

    def digraph( map, relation )
      n = relation.size
      index    = Array.new( n, nil )
      vertices = []
      @infinity = n + 2

      i = nil
      index.each_index do |i|
        if not index[i] and relation[i] then
          traverse i, index, vertices, map, relation
        end
      end
    end

    def traverse( i, index, vertices, map, relation )
      vertices.push i
      index[i] = height = vertices.size

      proci = nil
      if rp = relation[i] then
        rp.each do |proci|
          unless index[proci] then
            traverse proci, index, vertices, map, relation
          end
          if index[i] > index[proci] then
            # circulative recursion !!!
            index[i] = index[proci]
          end
          map[i] |= map[proci]
        end
      end

      if index[i] == height then
        while true do
          proci = vertices.pop
          index[proci] = @infinity
          break if i == proci

          map[proci] |= map[i]
        end
      end
    end

    ###

    def print_atab( idx, tab )
      tab.each_with_index do |i,ii|
        printf '%-20s', idx[ii].inspect
        p i
      end
    end

    def print_tab( idx, rel, tab )
      tab.each_with_index do |bin,i|
        print i, ' ', idx[i].inspect, ' << '; p rel[i]
        print '  '
        each_t( @symboltable, bin ) {|t| print ' ', t }
        puts
      end
    end
def print_tab_i( idx, rel, tab, i )
  bin = tab[i]
  print i, ' ', idx[i].inspect, ' << '; p rel[i]
  print '  '
  each_t( @symboltable, bin ) {|t| print ' ', t }
end

    def printb( i )
      each_t( @symboltable, i ) do |t|
        print t, ' '
      end
      puts
    end

    def each_t( tbl, set )
      i = ii = idx = nil
      0.upto( set.size ) do |i|
        (0..7).each do |ii|
          if set[ idx = i * 8 + ii ] == 1 then
            yield tbl[idx]
          end
        end
      end
    end


    #
    # resolve
    #

    def resolve( state )
      if state.conflict? then
        resolve_rr state, state.ritems
        resolve_sr state, state.stokens
      else
        if state.rrules.empty? then
          # shift
          state.stokens.each do |t|
            state.action[t] = @actions.shift( state.goto_table[t] )
          end
        else
          # reduce
          state.defact = @actions.reduce( state.rrules[0] )
        end
      end
    end

    def resolve_rr( state, r )
      pt = t = act = item = nil

      r.each do |item|
        item.each_la( @symboltable ) do |t|
          act = state.action[t]
          if act then
            Reduce === act or bug! "#{act.type} in action table"
            #
            # can't resolve R/R conflict (on t).
            #   reduce with upper rule as default
            #
            state.rr_conflict act.rule, item.rule, t
          else
            # not conflict
            state.action[t] = @actions.reduce( item.rule )
          end
        end
      end
    end

    def resolve_sr( state, s )
      stok = rtok = goto = act = nil

      s.each do |stok|
        goto = state.goto_table[stok]
        act = state.action[stok]

        unless act then
          # no conflict
          state.action[ stok ] = @actions.shift( goto )
        else
          unless Reduce === act then
            puts 'DEBUG -------------------------------'
            p stok
            p act
            state.action.each do |k,v|
              print k.inspect, ' ', v.inspect, "\n"
            end
            bug! "#{act.type} in action table"
          end

          # conflict on stok

          rtok = act.rule.prec
          case do_resolve_sr( stok, rtok )
          when :Reduce
            # action is already set

          when :Shift
            # overwrite
            act.decref
            state.action[ stok ] = @actions.shift( goto )

          when :Error
            act.decref
            state.action[ stok ] = @actions.error

          when :CantResolve
            # shift as default
            act.decref
            state.action[ stok ] = @actions.shift( goto )
            state.sr_conflict stok, act.rule
          end
        end
      end
    end
    
    ASSOC = {
      :Left     => :Reduce,
      :Right    => :Shift,
      :Nonassoc => :Error
    }
   
    def do_resolve_sr( stok, rtok )
      puts "resolve_sr: s/r conflict: rtok=#{rtok}, stok=#{stok}" if @d_prec

      unless rtok and rtok.prec then
        puts "resolve_sr: no prec for #{rtok}(R)" if @d_prec
        return :CantResolve
      end
      rprec = rtok.prec

      unless stok and stok.prec then
        puts "resolve_sr: no prec for #{stok}(S)" if @d_prec
        return :CantResolve
      end
      sprec = stok.prec

      ret = if rprec == sprec then
              ASSOC[ rtok.assoc ] or
                  bug! "#{rtok}.assoc is not Left/Right/Nonassoc"
            else
              if rprec > sprec then :Reduce else :Shift end
            end

      puts "resolve_sr: resolved as #{ret.id2name}" if @d_prec
      ret
    end


    #
    # complete
    #

    def set_accept
      anch = @symboltable.anchor
      init_state = @states[0].goto_table[ @ruletable.start ]
      targ_state = init_state.action[ anch ].goto_state
      acc_state  = targ_state.action[ anch ].goto_state

      acc_state.action.clear
      acc_state.goto_table.clear
      acc_state.defact = @actions.accept
    end

    def pack( state )
      ### find most frequently used reduce rule
      act = state.action
      arr = Array.new( @ruletable.size, 0 )
      t = a = nil
      act.each do |t,a|
        if Reduce === a then
          arr[ a.ruleid ] += 1
        end
      end
      i = arr.max
      s = i>0 ? arr.index(i) : nil

      ### set & delete default action
      if s then
        r = @actions.reduce(s)
        if not state.defact or state.defact == r then
          act.delete_if {|t,a| a == r }
          state.defact = r
        end
      else
        state.defact ||= @actions.error
      end
    end

    def check_useless
      act = nil
      used = []
      @actions.each_reduce do |act|
        if not act or act.refn == 0 then
          act.rule.useless = true
        else
          t = act.rule.target
          used[ t.ident ] = t
        end
      end
      @symboltable.nt_base.upto( @symboltable.nt_max - 1 ) do |n|
        unless used[n] then
          @symboltable[n].useless = true
        end
      end
    end

  end   # class StateTable


  #
  # State
  #
  # stands one lalr state.
  #

  class State

    def initialize( ident, core )
      @ident = ident
      @core  = core

      @goto_table = {}
      @gotos      = {}

      @stokens = nil
      @ritems = nil

      @action = {}
      @defact = nil

      @rrconf = nil
      @srconf = nil

      ###

      @closure = make_closure( @core )
    end


    attr :ident
    alias stateid ident
    alias hash ident

    attr :core
    attr :closure

    attr :goto_table
    attr :gotos

    attr :stokens
    attr :ritems
    attr :rrules

    attr :action
    attr :defact, true   # default action

    attr :rrconf
    attr :srconf

    def inspect
      "<state #{@ident}>"
    end

    alias to_s inspect

    def ==( oth )
      @ident == oth.ident
    end

    alias eql? ==


    def make_closure( core )
      set = ISet.new
      core.each do |ptr|
        set.add ptr
        if t = ptr.deref and t.nonterminal? then
          set.update_a t.expand
        end
      end
      set.to_a
    end

    def check_la( la_rules )
      @conflict = false
      s = []
      r = []
      @closure.each do |ptr|
        if t = ptr.deref then
          if t.terminal? then
            s[t.ident] = t
            if t.ident == 1 then   # $error
              @conflict = true
            end
          end
        else
          r.push ptr.rule
        end
      end
      unless r.empty? then
        if not s.empty? or r.size > 1 then
          @conflict = true
        end
      end
      s.compact!
      @stokens  = s
      @rrules = r

      if @conflict then
        @la_rules_i = la_rules.size
        @la_rules = r.collect {|i| i.ident }
        la_rules.concat r
      else
        @la_rules_i = @la_rules = nil
      end
    end

    def conflict?
      @conflict
    end

    def rruleid( rule )
      if i = @la_rules.index( rule.ident ) then
        @la_rules_i + i
      else
        puts '/// rruleid'
        p self
        p rule
        p @rrules
        p @la_rules_i
        bug! 'rruleid'
      end
    end

    def set_la( la )
      return unless @conflict

      i = @la_rules_i
      @ritems = r = []
      @rrules.each do |rule|
        r.push Item.new( rule, la[i] )
        i += 1
      end
    end

    def rr_conflict( high, low, ctok )
      c = RRconflict.new( @ident, high, low, ctok )

      @rrconf ||= {}
      if a = @rrconf[ctok] then
        a.push c
      else
        @rrconf[ctok] = [c]
      end
    end

    def sr_conflict( shift, reduce )
      c = SRconflict.new( @ident, shift, reduce )

      @srconf ||= {}
      if a = @srconf[shift] then
        a.push c
      else
        @srconf[shift] = [c]
      end
    end

  end   # State


  #
  # Goto
  #
  # stands one transition on the grammer.
  # REAL GOTO means transition by nonterminal,
  # but this class treats also terminal's.
  # If is terminal transition, .ident returns nil.
  #

  class Goto

    def initialize( ident, sym, from, to )
      @ident      = ident
      @symbol     = sym
      @from_state = from
      @to_state   = to
    end

    attr :ident
    attr :symbol
    attr :from_state
    attr :to_state
    
    def inspect
      "(#{@from_state.ident}-#{@symbol}->#{@to_state.ident})"
    end
  
  end


  #
  # Item
  #
  # lalr item. set of rule and its lookahead tokens.
  #

  class Item
  
    def initialize( rule, la )
      @rule = rule
      @la  = la
    end

    attr :rule
    attr :la

    def each_la( tbl )
      la = @la
      i = ii = idx = nil
      0.upto( la.size - 1 ) do |i|
        (0..7).each do |ii|
          if la[ idx = i * 8 + ii ] == 1 then
            yield tbl[idx]
          end
        end
      end
    end

  end


  #
  # ActionTable
  #
  # the table of lalr actions. Actions are
  # Shift, Reduce, Accept and Error
  #

  class ActionTable

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
        @reduce.push Reduce.new( rl )
      end
      @statetable.each do |st|
        @shift.push Shift.new( st )
      end
      @accept = Accept.new
      @error = Error.new
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
      if State === i then
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


  class Shift

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


  class Reduce

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


  #
  # Conflicts
  #

  class SRconflict

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

  class RRconflict
    
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

end
