#
# state.rb
#
#   Copyright (c) 1999 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#

require 'amstd/must'


module Racc

  class RaccError < StandardError; end


  class LALRstateTable

    def initialize( racc )
      @racc = racc
      @ruletable  = racc.ruletable
      @tokentable = racc.tokentable

      @d_state  = racc.d_state
      @d_reduce = racc.d_reduce
      @d_shift  = racc.d_shift
      @prof     = racc.d_prof

      @states = []
      @statecache = {}

      @actions = LALRactionTable.new( @ruletable, self )
    end
    

    attr :actions

    def size
      @states.size
    end


    def inspect
      "#<state table>"
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


    def init

      # add state 0
      seed_to_state( [ @ruletable[0].ptrs(0) ] )

      cur = 0
      while cur < @states.size do
        develop_state @states[cur]   # state is added here
        cur += 1
      end
    end


    def resolve
      $stderr.puts 'resolver start' if @prof

      @states.each do |state|
        state.compute_first_term
      end
      if @prof then
        b = Time.times.utime
        slr = 0
        lalr = 0
      end
      @states.each do |state|
        if @prof then
          if state.stateid % 40 == 39 then
            $stderr.puts "end #{state.stateid + 1} states"
          end
        end

        if state.conflicting? then
          ret = state.resolve
          if ret == :slr then slr += 1 else lalr += 1 end if @prof
        end
      end

      if @prof then
        e = Time.times.utime
        puts "total #{e - b} sec"
        puts "slr #{slr}, lalr #{lalr}"
        $stderr.puts 'resolve ok'
      end

      # set accept

      anch = @tokentable.anchor
      init_state = @states[0].nonterm_table[ @ruletable.start ]
      targ_state = init_state.action[ anch ].goto_state
      acc_state  = targ_state.action[ anch ].goto_state

      acc_state.action.clear
      acc_state.nonterm_table.clear
      acc_state.defact = @actions.accept

      simplify   #not_simplify
    end


    private

    
    def develop_state( state )
      puts "develop_state: #{state}" if @d_state

      devseed = {}
      rp = state.reduce_ptrs
      tt = state.term_table
      nt = state.nonterm_table

      state.closure.each do |ptr|
        if ptr.reduce? then
          rp.push ptr
        else
          tok = ptr.unref
          if tok.terminal? then tt[ tok ] = true
                           else nt[ tok ] = true
          end

          if arr = devseed[ tok ] then
            arr.push ptr.increment
          else
            devseed[ tok ] = [ ptr.increment ]
          end
        end
      end

      devseed.each do |tok, seed|
        # all 'seed's must be rule table order (upper to lower)
        seed.sort!{|a, b| a.hash <=> b.hash }

        puts "devlop_state: tok=#{tok} nseed=#{seed.join(' ')}" if @d_state

        dest = seed_to_state( seed )
        connect( state, tok, dest )
      end
    end


    def seed_to_state( seed )
      unless dest = @statecache[seed] then
        # not registered yet
        dest = LALRstate.new( @states.size, seed, @racc )
        @states.push dest

        @statecache[ seed ] = dest
        
        puts "seed_to_state: create state   ID #{dest.stateid}" if @d_state
      else
        if @d_state then
          puts "seed_to_state: dest is cached ID #{dest.stateid}"
          puts "seed_to_state: dest seed #{dest.seed.join(' ')}"
        end
      end

      dest
    end


    def connect( from, tok, dest )
      puts "connect: #{from.stateid} --(#{tok})-> #{dest.stateid}" if @d_state

      # check infinite recursion
      if from.stateid == dest.stateid and from.closure.size < 2 then
        raise RaccError, sprintf( "Infinite recursion: state %d, with rule %d",
          from.stateid, from.ptrs[0].ruleid )
      end

      # goto
      if tok.terminal? then
        from.term_table[ tok ] = dest
      else
        from.nonterm_table[ tok ] = dest
      end

      # come from
      if tmp = dest.from_table[ tok ] then
        tmp[ from ] = true
      else
        dest.from_table[ tok ] = { from => true }
      end
    end


    def not_simplify
      err = @actions.error
      @states.each do |st|
        st.defact ||= err
      end
    end

    def simplify
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

  end   # LALRstateTable


  class SLRerror < StandardError; end


  class LALRstate

    def initialize( sid, seed, racc )
      @stateid = sid
      @seed = seed

      @closure = nil
      @closure_hash = nil

      @racc       = racc
      @tokentable = racc.tokentable
      @actions    = racc.statetable.actions
      @d_state    = racc.d_state
      @d_reduce   = racc.d_reduce
      @d_shift    = racc.d_shift
      @prof       = racc.d_prof

      @from_table    = {}
      @term_table    = {}
      @nonterm_table = {}

      @first_term = {}
      @nullable = []

      @shift_toks  = []
      @reduce_ptrs = []
      @reduce_seed = []

      @action = {}
      @defact = nil

      @resolve_log = []

      @rrconf = nil
      @srconf = nil

      init_values
    end

    def init_values
      @reduce_seed = seed.find_all {|ptr| ptr.reduce? }

      @seed.each do |ptr|
        t = ptr.unref
        if t and t.nullable? then
          @nullable.push t
        end
      end

      @closure = compute_closure( @seed )
    end

    def compute_closure( ptrs )
      puts "closure: ptrs=#{ptrs.join(' ')}" if @d_state

      @closure_hash = tmp = {}
      tok = a = b = nil

      ptrs.each do |ptr|
        tmp[ ptr ] = true

        tok = ptr.unref
        if tok and not tok.terminal? then
          tmp.update tok.expand
        end
      end

      ret = tmp.keys
      ret.sort!{|a,b| a.hash <=> b.hash }

      puts "closure: ret #{ret.join(' ')}" if @d_state
      ret
    end


    attr :stateid
    attr :closure
    attr :closure_hash

    attr :seed

    attr :from_table
    attr :term_table
    attr :nonterm_table

    attr :nullable
    attr :first_term

    attr :reduce_ptrs
    attr :reduce_seed

    attr :action
    attr :defact, true   # default action

    attr :resolve_log

    attr :rrconf
    attr :srconf

    def inspect
      "#<LALRstate #{@stateid}>"
    end
    alias to_s inspect


    def ==( oth )
      @stateid == oth.stateid
    end

    def eql?( oth )
      @seed == oth.seed
    end

    def hash
      @stateid
    end

    def each_ptr( &block )
      @closure.each( &block )
    end


    def conflicting?
      if @reduce_ptrs.size > 0 then
        if @closure.size == 1 then
          @defact = @actions.reduce( @reduce_ptrs[0].rule )
          #
          # reduce
          #
        else
          #
          # conflict
          #
          return true
        end
      else
        #
        # shift
        #
        @term_table.each do |tok, goto|
          @action[ tok ] = @actions.shift( goto )
        end
      end

      false
    end


    def resolve
      if @d_reduce or @d_shift then
        puts "resolving state #{@stateid} -------------"
      end

      @method = :slr
      begin
        resolve_rr
        resolve_sr
      rescue SLRerror
        if @d_reduce or @d_shift then
          puts "state #{@stateid}, slr fail -------------"
        end
        @action.clear
        @method = :lalr
        retry
      end

      @method
    end


    #
    #  Reduce/Reduce Conflict resolver
    #

#trap( 'INT' ) do
#puts "resolving #{$resolving_state.stateid}"; $stdout.flush
#raise Exception, "stopped by SIGINT"
#end

    def resolve_rr
#$resolving_state = self
      puts "resolve_rr: state #{@stateid}, #{method.id2name}" if @d_reduce

      la = act = curptr = tok = nil

      @reduce_ptrs.each do |curptr|
        puts "resolve_rr: resolving #{curptr}" if @d_reduce

        la = send( @method, curptr )
        la.each_key do |tok|
          act = @action[ tok ]
          if act then
            unless ReduceAction === act then
              bug! "no reduce action #{act.type} in action table"
            end
            #
            # can't resolve R/R conflict (on tok).
            #   reduce with upper rule as default
            #

            rr_conflict act.rule, curptr.rule, tok
          else
            # not conflict
            @action[ tok ] = @actions.reduce( curptr.rule )
          end
        end
      end
    end


    def slr( ptr )
      ptr.rule.simbol.follow
    end


    def lalr( ptr )
      ret = lookahead( ptr, [] )
      puts "LA: state #{@stateid}: #{ret.keys.join(' ')}" if @d_reduce
      ret
    end

    def compute_first_term
      h = @first_term

      h.update @term_table
      @nonterm_table.each_key do |tok|
        h.update tok.first
      end
    end


    def lookahead( ptr, lock )
      puts "la> state #{@stateid},#{ptr}" if @d_reduce
      st_beg = Time.times.utime if @prof

      sim = ptr.rule.simbol
      ret = {}
      gotos = {}
      new = {}
      goto = pt = nil
      ff = len = nil
      f = a = tmp = nil
      nt = h = nil

      head_state( ptr ).each_key do |f|
        tmp = f.nonterm_table[ sim ]
        if a = gotos[tmp]; a[f]=1 else gotos[tmp] = {f,1} end
      end

      i = 0 if @prof
      until gotos.empty? do
        i += 1 if @prof

        gotos.each do |goto, froms|
          puts "la: goto #{goto.stateid}" if @d_reduce

          next if lock[goto.stateid]
          lock[goto.stateid] = true
          ret.update goto.first_term

  goto.reduce_seed.each do |pt|
    sim = pt.rule.simbol

    froms.each do |f,len|
      if pt.index == len then
                  tmp = f.nonterm_table[ sim ]
#unless tmp then p goto.stateid; p f.stateid; p pt; bug! end
                  if h = new[tmp]; h[f]=1 else new[tmp] = {f,1} end
      else
#begin
        f.head_state( pt.before(len) ).each_key do |ff|
                  tmp = ff.nonterm_table[ sim ]
#unless tmp then p goto.stateid; p ff.stateid; p pt; bug! end
                  if h = new[tmp]; h[ff]=1 else new[tmp] = {ff,1} end
        end
#rescue FindBug
#p f
#p len
#p pt
#raise
#end
      end
    end
  end           # seed.each
  goto.nullable.each do |nt|
                  tmp = goto.nonterm_table[ nt ]
#unless tmp then p goto.stateid; p ff.stateid; p pt; bug! end
                  if h = new[tmp] then
                    froms.each {|f,len| bug! if h[f]; h[f] = len + 1 }
                  else
                    h = {}; froms.each {|f,len| h[f] = len + 1 }
                    new[tmp] = h
                  end
  end
        end     # gotos.each

        tmp = gotos
        gotos = new
        new = tmp
        new.clear
      end            # until

      if @prof
        st_end = Time.times.utime
        printf "%-4d %4d %4d %f\n",
               @stateid, lock.compact.size, i, st_end - st_beg
      end

      puts "la< state #{@stateid}" if @d_reduce
      ret
    end

    def head_state( ptr )
      puts "hs> ptr #{ptr}" if @d_reduce

      cur = { self => true }
      new = {}
      backed = st = nil

      until ptr.head? do
        ptr = ptr.decrement
        tok = ptr.unref

        cur.each_key do |st|
          unless backed = st.from_table[ tok ] then
#p st.from_table
#p tok
#puts "from table void: state #{st.stateid} key '#{tok}'"
#$stdout.flush
            bug! "from table void: state #{st.stateid} key #{tok}"
          end
          new.update backed
        end

        tmp = cur
        cur = new
        new = tmp
        new.clear
      end

      puts "hs< backed [#{sh2s cur}]" if @d_reduce
      cur
    end

    def sh2s( sh )
      sh.collect{|s,v| s.stateid }.join(',')
    end


    #
    # Shift/Reduce Conflict resolver
    #

    def resolve_sr

      @term_table.each do |stok, goto|

        unless act = @action[ stok ] then
          # no conflict
          @action[ stok ] = @actions.shift( goto )
        else
          case act
          when ShiftAction
            # already set to shift

          when ReduceAction
            # conflict on stok

            rtok = act.rule.prec
            ret  = do_resolve_sr( stok, rtok )

            case ret
            when :Reduce        # action is already set

            when :Shift         # overwrite
              @action[ stok ] = @actions.shift( goto )

            when :Remove        # remove
              @action.delete stok

            when :CantResolve   # shift as default
              @action[ stok ] = @actions.shift( goto )
              sr_conflict stok, act.rule
            end
          else
            bug! "wrong act in action table: #{act}(#{act.type})"
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
      if @method == :slr then
        raise SLRerror, "SLR r/r conflict in state #{@stateid}"
      end
        
      c = RRconflict.new( @stateid, high, low, ctok )

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
      if @method == :slr then
        raise SLRerror, "SLR s/r conflict in state #{@stateid}"
      end

      c = SRconflict.new( @stateid, shift, reduce )

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

    def initialize( rl, st )
      @ruletable = rl
      @statetable = st

      @reduce = []
      @shift = []
      @accept = nil
      @error = nil
    end


    def reduce_n
      @reduce.size
    end

    def reduce( i )
      if Rule === i then
        i = i.ruleid
      else
        i.must Integer
      end

      unless ret = @reduce[i] then
        @reduce[i] = ret = ReduceAction.new( @ruletable[i] )
      end

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
        i = i.stateid
      else
        i.must Integer
      end

      unless ret = @shift[i] then
        @shift[i] = ret = ShiftAction.new( @statetable[i] )
      end

      ret
    end

    def each_shift( &block )
      @shift.each &block
    end


    def accept
      unless @accept then
        @accept = AcceptAction.new
      end

      @accept
    end

    def error
      unless @error then
        @error = ErrorAction.new
      end

      @error
    end

  end


  class LALRaction
  end


  class ShiftAction < LALRaction

    def initialize( goto )
      goto.must LALRstate
      @goto_state = goto
    end

    attr :goto_state

    def goto_id
      @goto_state.stateid
    end

    def inspect
      "<shift #{@goto_state.stateid}>"
    end

  end


  class ReduceAction < LALRaction

    def initialize( rule )
      rule.must Rule
      @rule = rule
    end

    attr :rule

    def ruleid
      @rule.ruleid
    end

    def inspect
      "<reduce #{@rule.ruleid}>"
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
               @stateid, @high_prec.ruleid, @low_prec.ruleid, @token.to_s )
    end

  end

end   # module Racc
