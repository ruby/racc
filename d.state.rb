
  class LALRstateTable

    def initialize( racc )
      @racc = racc
      @ruletable  = racc.ruletable
      @tokentable = @ruletable.tokentable
      @prectable  = racc.prectable

      @d_state  = racc.d_state
      @d_reduce = racc.d_reduce
      @d_shift  = racc.d_shift

      @states = []
      @statecache = {}
    end
    

    def each_state
      @states.each{|st| yield st }
    end

    def to_a
      @states
    end

    def to_s
      "<LALRstateTable size #{@states.size}>"
    end


    def do_initialize
      # add first state (ID 0)
      add_new_state [ @ruletable[0].ptrs(0) ]

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
            puts "resolve state #{state.stateid} -------------"
          end

          ### default

          # de   = @tokentable.get_token( Parser::Default )
          # rptr = state.reduce_ptrs[0]
          # goto = state.goto_state_from_rptr
          # act[ de ] = ReduceAction.new( goto, rptr.rule )

          ### resolve

          state.resolve_rr
          state.resolve_sr
        end
      end
    end


    private

    
    def develop_state( state )
      puts "develop_state: start\n#{state.inspect}" if @d_state

      state.next_seed.each do |tok, arr|
        # all 'arr's must be same order
        # (rule table order, upper to lower)
        arr.sort!{|a, b| a.hash <=> b.hash }

        puts "init_state: each: tok=#{tok} arr=#{arr.join(' ')}" if @d_state

        unless dest = @statecache[arr] then
          # not registered yet
          dest = add_new_state( arr, hash )
          
          puts "init_state: create dest.    ID #{dest.stateid}" if @d_state
        else
          if @d_state then
            puts "init_state: dest is cached. ID #{dest.stateid}"
            puts "init_state: dest seed #{dest.seed.join(' ')}"
          end
        end

        state.is_goto( tok, dest )
        dest.is_from( tok, state )
      end
    end


    def add_new_state( seed )
      lr_closure = closure( seed )

      ns = {}   # next seed
      rp = []   # reduce ptrs
      sp = []   # shift ptrs
      st = {}   # shift tokens

      lr_closure.each do |ptr|
        if ptr.reduce? then
          rp.push ptr
        else
          sp.push ptr

          tok = ptr.unref
          if tok.terminal? then
            st[ tok ] = true
          end

          inc = ptr.increment

          if hash = ns[ tok ] then
            hash[ inc ] = true
          else
            ns[ tok ] = { inc => true }
          end
        end
      end
      st = st.keys

      tmp = LALRstate.new( @states.size, lr_closure,
                           seed, ns,
                           sp, st, rp,
                           @racc )
      @states.push tmp
      @statecache[ seed ] = tmp

      tmp
    end


    def closure( orig_ptrs )
      puts "closure: start: ptrs #{ptrs.join(' ')}" if @d_state

      ptrs = orig_ptrs.dup
      temp = {}

      ptrs.each do |ptr|
        temp[ ptr ] = true

        tok = ptr.unref
        ptr.reduce? or tok.terminal? or temp.update( tok.expand )
      end
      ret = temp.keys
      ret.sort!{|a,b| a.hash <=> b.hash }

      @d_state and puts "closure: ret #{ret.join(' ')}"
      ret
    end

  end   # LALRstateTable



  class LALRstate

    attr :stateid
    attr :ptrs

    attr :seed
    attr :next_seed

    attr :action
    attr :reduce_ptrs
    attr :shift_ptrs

    attr :goto_table
    attr :from_table


    def initialize( state_id, lr_closure,
                    seed, next_seed,
                    shift_ptrs, shift_toks, reduce_ptrs,
                    racc )

      @stateid      = state_id
      @ptrs         = lr_closure

      @seed         = seed
      @develop_seed = next_seed

      @reduce_ptrs  = reduce_ptrs
      @shift_ptrs   = shift_ptrs
      @shift_toks   = shift_toks

      @racc    = racc
      @ruletable  = racc.ruletable
      @d_reduce   = racc.d_reduce
      @d_shift    = racc.d_shift

      @from_table = {}
      @goto_table = {}

      @lookahead = nil

      @action = {}

      @rrconf = []
      @srconf = []
    end


    def ==( oth )
      @stateid == oth.stateid
    end

    def eql?( oth )
      @seed == oth.seed
    end

    def stateeq( oth )
      @stateid == oth.stateid
    end

    def seedeq( oth )
      @seed == oth
    end

    def hash
      @stateid
    end

    def size
      @ptrs.size
    end

    def to_s
      "<LALR state #{@stateid}>"
    end

    def inspect
      "state #{@stateid}\n" + @ptrs.join("\n")
    end

    def each_ptr
      @ptrs.each{|ptr| yield ptr }
    end


    def is_goto( tok, dest )

      # check infinite recursion
      did = dest.stateid
      if @stateid == did and size < 2 then
        rid = dest.ptrs[0].ruleid
        @racc.logic.push "Infinite recursion: state #{did}, with rule #{rid}"
      end

      # goto
      @goto_table[ tok ] = dest
    end

    
    def is_from( tok, state )
      if temp = @from_table[ tok ] then
        temp.push state
      else
        @from_table[ tok ] = [ state ]
      end
    end


    def conflicting?
      if @reduce_ptrs.size > 0 then
        if @ptrs.size == 1 then
          @action[ ] = ReduceAction.new
        else
          return true
        end
      else
        @action = ShiftAction.new
      end

      return false
    end


    def resolve_sr

      @shift_toks.each do |stok|
        goto_st = @goto_table[ stok ]

        unless act = @action[ stok ] then
          # no conflict
          @action[ stok ] = ShiftAction.new( goto_st )
        else
          if ReduceAction === act then
            # conflict on stok
            rtok = act.rule.prec
            ret = do_resolve_sr( stok, rtok )

            case ret
            when :Reduce
              # action is already set

            when :Shift
              # overwrite
              @action[ stok ] = ShiftAction.new( goto_st )

            when :Remove
              # remove action
              @action.delete stok

            when :CantResolve
              # shift to default
              @action[ stok ] = ShiftAction.new( goto_st )
              srconf stok, act.rule

            else
              bug! "do_resolve_sr return wrong val: #{ret}"
            end
          else
            # already set to shift
          end
        end
      end
    end


    def resolve_rr
      @reduce_ptrs.each do |curptr|
        puts "resolve_rr: each: state #{@stateid}, #{curptr}" if @d_reduce

        la_toks( curptr ).each_key do |tok|
          act = @action[ tok ]
          if ReduceAction === act then
            #
            # can't resolve R/R conflict (on tok),
            #   reduce with upper rule as default
            #
            rrconf act.rule, curptr.rule, tok
          else
            # resolved
            goto_st = @goto_table[ tok ]
            @action[ tok ] = ReduceAction.new( goto_st, curptr.rule )
          end
        end
      end
    end


    def lookahead( idlock )
      puts "lookahead: state #{@stateid}" if @d_reduce

      idlock[ @stateid ] = true         # recurcive lock
      return @lookahead if @lookahead   # cached

      ret  = {}
      tmp = {}

      @next_seed.each_key do |tok|
        ret.update tok.first
        if tok.nullp then
          tmp[ @goto_table[ tok ] ] = true
        end
      end
      @reduce_ptrs.each do |ptr|
        tmp.update backtrack( ptr )
      end

      tmp.each_key do |st|
        unless idlock[ st.stateid ] then
          ret.update st.lookahead( idlock )
        end
      end
      @lookahead = ret

      puts "lookahead: lookahead #{ret.keys.join(' ')}" if @d_reduce

      return ret
    end



    private

    
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

    
    def la_toks( ptr )
      ret = {}

      backtrack( ptr ).each do |st|
        ret.update st.lookahead([])
      end

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
            con_bug! st, tok
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
      cur.each_key{|st| ret[ st.goto_table[ sim ] ] = true }

      puts "backtrack: from #{@stateid} to #{sh2s ret}" if @d_reduce

      ret
    end

    # simbol hash to string
    def sh2s( sh )
      '[' + sh.collect {|s| s.stateid }.join(' ') + ']'
    end

    def con_bug!( st, tok )
      bug! "from table void: state #{st.stateid} key #{tok}"
    end


    def rrconf( rule1, rule2, tok )
      @racc.rrconf.push RRconflict.new( @stateid, rule1, rule2, tok )
    end

    def srconf( stok, rrule )
      @racc.srconf.push SRconflict.new( @stateid, stok, rrule )
    end

  end   # LALRstate

  

  class LALRaction

    def initialize( goto )
      @goto_state = goto
    end

    attr :goto_state

  end


  class ShiftAction < LALRaction

    def to_s
      '<action Shift>'
    end

  end


  class ReduceAction < LALRaction

    def initialize( goto, rule )
      @goto_state = goto
      @rule = rule
    end

    def to_s
      '<action Reduce>'
    end

    attr :rule

  end


  class ConflictData ; end

  class SRconflict < ConflictData

    attr :stateid
    attr :shift
    attr :reduce
  
    def initialize( sid, stok, rrule )
      @stateid = sid
      @shift   = stok
      @reduce  = rrule
    end
    
    def to_s
      str = sprintf(
        'state %d: S/R conflict rule %d reduce and shift %s',
        @stateid,
        @reduce.ruleid,
        @shift.to_s
      )
    end
  end

  class RRconflict < ConflictData
    
    attr :stateid
    attr :reduce1
    attr :reduce2
    attr :token
  
    def initialize( sid, rule1, rule2, tok )
      @stateid = sid
      @reduce1 = rule1
      @reduce2 = rule2
      @token   = tok
    end

    def to_s
      str =  sprintf(
        'state %d: R/R conflict with rule %d and %d on %s',
        @stateid,
        @reduce1.ruleid,
        @reduce2.ruleid,
        @token.to_s
      )
    end

  end
