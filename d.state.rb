
  class LALRstateTable

    def initialize( racc )
      @racc = racc
      @ruletable  = racc.ruletable
      @tokentable = racc.tokentable

      @d_state  = racc.d_state
      @d_reduce = racc.d_reduce
      @d_shift  = racc.d_shift

      @states = []
      @statecache = {}
    end
    

    def each_state( &block )
      @states.each( &block )
    end
    alias each each_state

    def each_index( &block )
      @states.each_index( &block )
    end

    def to_s
      "<LALR state table: #{@states.size} states>"
    end


    def do_initialize
      # add state 0
      seed_to_state( [ @ruletable[0].ptrs(0) ] )

      cur = 0
      while cur < @states.size do
        develop_state @states[cur]   # state is added here
        cur += 1
      end
    end


    def resolve
      @states.each do |state|
        if state.conflicting? then
          if @d_reduce or @d_shift then
            puts "resolving state #{state.stateid} -------------"
          end

          state.resolve_rr
          state.resolve_sr
        end
      end

      # set accept

      anch = @tokentable.anchor
      s = @states[0].nonterm_table[ @ruletable.start ]
      s = s.action[ anch ].goto_state
      s = @states[s]
      s = s.action[ anch ].goto_state
      s = @states[s]
      s.action.clear
      s.nonterm_table.clear
      s.action[ @tokentable.default ] = AcceptAction.new

      enshort   #not_enshort
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

      devseed.each do |tok, arr|
        # all 'arr's must be rule table order (upper to lower)
        arr.sort!{|a, b| a.hash <=> b.hash }

        puts "devlop_state: tok=#{tok} nseed=#{arr.join(' ')}" if @d_state

        dest = seed_to_state( arr )
        connect( state, tok, dest )
      end
    end


    def seed_to_state( seed )
      unless dest = @statecache[seed] then
        # not registered yet
        lr_closure = closure( seed )
        dest = LALRstate.new( @states.size, lr_closure, seed, @racc )
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


    def closure( ptrs )
      puts "closure: ptrs=#{ptrs.join(' ')}" if @d_state

      tmp = {}
      ptrs.each do |ptr|
        tmp[ ptr ] = true

        tok = ptr.unref
        if not ptr.reduce? and not tok.terminal? then
          tmp.update( tok.expand )
        end
      end
      ret = tmp.keys
      ret.sort!{|a,b| a.hash <=> b.hash }

      puts "closure: ret #{ret.join(' ')}" if @d_state
      ret
    end


    def connect( from, tok, dest )
      puts "connect: #{from.stateid} --(#{tok})-> #{dest.stateid}" if @d_state

      # check infinite recursion
      if from.stateid == dest.stateid and from.closure.size < 2 then
        @racc.logic.push sprintf( "Infinite recursion: state %d, with rule %d",
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


    def not_enshort
      deft = @tokentable.default
      @states.each do |st|
        st.action[deft] ||= ErrorAction.new
      end
    end

    def enshort
      arr = []
      act = nil
      i = nil
      deft = @tokentable.default
      dflt = nil

      @states.each do |st|
        #
        # find most used reduction
        #
        act = st.action
        (@ruletable.size - 1).downto(0){|i| arr[i] = 0 }
        act.each do |t,a|
          if ReduceAction === a then
            arr[a.rule.ruleid] += 1
          end
        end
        i = 1
        s = nil
        arr.each_with_index do |n,idx|
          if n > i then
            i = n
            s = idx
          end
        end

        dflt = act[deft]
        if s then
          r = ReduceAction::Instance[s]
          if not dflt or dflt == r then
            act.delete_if {|t,a| a == r }
            act[deft] = r
          end
        else
          act[deft] = ErrorAction.new unless dflt
        end
      end
    end

  end   # LALRstateTable



  class LALRstate

    attr :stateid
    attr :closure

    attr :seed

    attr :from_table
    attr :term_table
    attr :nonterm_table

    attr :reduce_ptrs

    attr :action


    def initialize( state_id, lr_closure, seed, racc )

      @stateid = state_id
      @closure = lr_closure

      @seed = seed

      @racc      = racc
      @tokentable = racc.tokentable
      @d_reduce  = racc.d_reduce
      @d_shift   = racc.d_shift

      @from_table    = {}
      @term_table    = {}
      @nonterm_table = {}

      @reduce_ptrs = []
      @shift_toks  = []

      @action = {}

      @first_terms = nil

      @rrconf = []
      @srconf = []
    end


    def ==( oth )
      @stateid == oth.stateid
    end

    def eql?( oth )
      @seed == oth.seed
    end

    def hash
      @stateid
    end

    def to_s
      sprintf( '<state %d %s>', @stateid, @closure.join(' ') )
    end
    alias inspect to_s

    def each_ptr( &block )
      @closure.each( &block )
    end


    def conflicting?
      if @reduce_ptrs.size > 0 then
        if @closure.size == 1 then
          @action[ @tokentable.default ] = ReduceAction.new( @closure[0].rule )
        else
          return true
        end
      else
        @term_table.each do |tok, goto|
          @action[ tok ] = ShiftAction.new( goto.stateid )
        end
      end

      return false
    end


    #
    #  Reduce/Reduce Conflict resolver
    #

    def resolve_rr
      puts "resolve_rr: state #{@stateid}" if @d_reduce

      act = curptr = tok = nil

      @reduce_ptrs.each do |curptr|
        puts "resolve_rr: each: #{curptr}" if @d_reduce

        lookahead_tokens( curptr ).each_key do |tok|
          act = @action[ tok ]
          if ReduceAction === act then
            #
            # can't resolve R/R conflict (on tok),
            #   reduce with upper rule as default
            #
            rrconf act.rule, curptr.rule, tok
          else
            # resolved
            @action[ tok ] = ReduceAction.new( curptr.rule )
          end
        end
      end
    end

    
    def lookahead_tokens( ptr )
      puts "lookahead: start ptr=#{ptr}" if @d_reduce

      ret = {}
      backtrack( ptr ).each_key do |st|
        ret.update st.first_terms([])
      end

      puts "lookahead: ret [#{ret.keys.join(' ')}]" if @d_reduce
      return ret
    end


    def backtrack( ptr )
      cur = { self => true }
      newstates = {}
      backed = nil

      puts "backtrack: start: state #{@stateid}, ptr #{ptr}" if @d_reduce

      until ptr.head? do
        ptr = ptr.decrement
        tok = ptr.unref

        cur.each_key do |st|
          unless backed = st.from_table[ tok ] then
            bug! "from table void: state #{st.stateid} key #{tok}"
          end
          newstates.update backed
        end

        tmp = cur
        cur = newstates
        newstates = tmp
        newstates.clear
      end

      sim = ptr.rule.simbol
      ret = newstates
      cur.each_key do |st|
        t = st.nonterm_table[ sim ]
        ret[t] = true if t
      end

      puts "backtrack: from #{@stateid} to #{sh2s ret}" if @d_reduce
      ret
    end

    def sh2s( sh )
      '[' + sh.collect{|s,v| s.stateid }.join(' ') + ']'
    end


    def first_terms( idlock )
      idlock[ @stateid ] = true             # recurcive lock
      return @first_terms if @first_terms   # cached

      puts "first_terms: state #{@stateid} ---" if @d_reduce

      ret = {}   # hash of look-ahead token
      tmp = {}   # backtrack-ed states

      @term_table.each do |tok, goto|
        ret[ tok ]  = true
      end
      @nonterm_table.each do |tok, goto|
        ret.update tok.first
        if tok.null? then
          tmp[ goto ] = true
        end
      end
      @reduce_ptrs.each do |ptr|
        tmp.update backtrack( ptr )
      end

      tmp.each_key do |st|
        unless idlock[ st.stateid ] then
          ret.update st.first_terms( idlock )
        end
      end
      @first_terms = ret

      puts "first_terms: state #{@stateid} [#{ret.keys.join(' ')}]" if @d_reduce

      ret
    end


    #
    # Shift/Reduce Conflict resolver
    #

    def resolve_sr

      @term_table.each do |stok, goto|

        unless act = @action[ stok ] then
          # no conflict
          @action[ stok ] = ShiftAction.new( goto.stateid )
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
              @action[ stok ] = ShiftAction.new( goto.stateid )

            when :Remove        # remove
              @action.delete stok

            when :CantResolve   # shift as default
              @action[ stok ] = ShiftAction.new( goto.stateid )
              srconf stok, act.rule
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

      if rprec == sprec then
        case rtok.assoc
        when :Left     then ret = :Reduce
        when :Right    then ret = :Shift
        when :Nonassoc then ret = :Remove  # 'rtok' raises ParseError
        else
          bug! "prec is not Left/Right/Nonassoc, #{rtok}"
        end
      else
        if rprec > sprec then
          ret = (if @reverse then :Shift else :Reduce end)
        else
          ret = (if @reverse then :Reduce else :Shift end)
        end
      end

      puts "resolve_sr: resolved as #{ret.id2name}" if @d_state

      return ret
    end
    private :do_resolve_sr



    def rrconf( rule1, rule2, tok )
      @racc.rrconf.push RRconflict.new( @stateid, rule1, rule2, tok )
    end

    def srconf( stok, rrule )
      @racc.srconf.push SRconflict.new( @stateid, stok, rrule )
    end

  end   # LALRstate



  class LALRaction
  end


  class ShiftAction < LALRaction

    Instance = []
    
    class << self

      alias orig_new new

      def new( goto )
        unless ret = self::Instance[ goto ] then
          self::Instance[ goto ] = ret = orig_new( goto )
        end

        ret
      end

      def each_instance
        Instance.each{|obj| yield obj if obj }
      end

    end

    def initialize( goto )
      @goto_state = goto
    end

    attr :goto_state

    def inspect
      "<shift #{@goto_state}>"
    end

  end


  class ReduceAction < LALRaction

    Instance = []

    class << self

      alias orig_new new

      def new( rule )
        unless ret = self::Instance[ rule.ruleid ] then
          self::Instance[ rule.ruleid ] = ret = orig_new( rule )
        end

        ret
      end

      def each_instance
        Instance.each{|obj| yield obj if obj }
      end

    end

    def initialize( rule )
      @rule = rule
    end

    attr :rule

    def inspect
      "<reduce #{@rule.ruleid}>"
    end

  end


  class AcceptAction < LALRaction

    Instance = []

    class << self
      alias orig_new new
      def new
        Instance[0] || orig_new
      end
    end

    def inspect
      "<accept>"
    end

  end


  class ErrorAction < LALRaction

    Instance = []

    class << self
      alias orig_new new
      def new
        Instance[0] || orig_new
      end
    end

    def inspect
      "<error>"
    end
  
  end


  class ConflictData ; end

  class SRconflict < ConflictData

    def initialize( sid, stok, rrule )
      @stateid = sid
      @shift   = stok
      @reduce  = rrule
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
    
    def initialize( sid, rule1, rule2, tok )
      @stateid = sid
      @reduce1 = rule1
      @reduce2 = rule2
      @token   = tok
    end

    attr :stateid
    attr :reduce1
    attr :reduce2
    attr :token
  
    def to_s
      sprintf( 'state %d: R/R conflict with rule %d and %d on %s',
               @stateid, @reduce1.ruleid, @reduce2.ruleid, @token.to_s )
    end

  end
