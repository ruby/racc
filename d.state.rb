
  class LALRstatTable

    def initialize( rac )
      @racc = rac
      @ruletable  = rac.ruletable
      @tokentable = @ruletable.tokentable
      @prectable  = rac.prectable

      @d_state  = rac.d_state
      @d_reduce = rac.d_reduce
      @d_shift  = rac.d_shift

      @stats = []
      @statcache = {}
    end
    

    def each_state
      @stats.each{|st| yield st }
    end

    def to_a() @stats end

    def to_s() "<LALRstatTable size #{@stats.size}>" end


    def do_initialize
      # add start closure
      add_new_state( [ @ruletable[0].ptrs(0) ] )

      cur = 0
      while cur < @stats.size do
        
        # state is added in develop_state
        develop_state( @stats[cur] )
        cur += 1
      end
    end


    def resolve
      @stats.each do |stat|
        act = stat.action
        if act.type == LookaheadAction then

          (@d_reduce or @d_shift) and
            puts "resolve state #{stat.stateid} -----------------"

          ### default

          de   = @tokentable.get_token( Parser::Default )
          rptr = stat.reduce_ptrs[0]
          act.store( de, ReduceAction.new(rptr) )

          ### resolve

          stat.resolve_rr
          stat.resolve_sr
        end
      end
    end


    private

    
    def develop_state( stat )
      @d_state and
        puts "develop_state: start\n#{stat.inspect}"

      stat.develop_seed.each do |tok, arr|
        @d_state and
          puts "init_stat: each: tok #{tok}, arr #{arr.join(' ')}"

        # 'arr's must be same order
        # (rule table order, upper to lower)
        arr.sort! do |a, b| a.hash <=> b.hash end

        unless (dest = @statcache[arr]) then
          # not registered yet
          dest = add_new_state( arr )
          
          @d_state and
            puts "init_stat: create dest.    ID #{dest.stateid}"
        else
          if @d_state then
            puts "init_stat: dest is cached. ID #{dest.stateid}"
            puts "init_stat: dest seed #{dest.seed.join(' ')}"
          end
        end

        stat.is_goto( tok, dest )
        dest.is_from( tok, stat )
      end
    end


    def add_new_state( seed )
      temp = LALRstat.new(
        closure( seed ),
        @stats.size,
        seed,
        @racc
      )
      @stats.push temp
      @statcache.store( seed, temp )

      return temp
    end


    def closure( orig_ptrs )
      ptrs = orig_ptrs.uniq
      @d_state and puts "closure: start: ptrs #{ptrs.join(' ')}"

      temp = {}
      ptrs.each do |ptr|
        temp.store( ptr, true )

        tok = ptr.unref
        ptr.reduce? or tok.term or temp.update( tok.expand )
      end
      ret = temp.keys
      ret.sort!{|a,b| a.hash <=> b.hash }

      @d_state and puts "closure: ret #{ret.join(' ')}"
      return ret
    end

  end   # LALRstatTable



  class LALRstat

    attr :stateid
    attr :ptrs

    attr :seed
    attr :develop_seed

    attr :action
    attr :reduce_ptrs
    attr :shift_ptrs

    attr :goto_table
    attr :from_table


    def initialize( arr, sid, sed, rac )
      @ptrs    = arr
      @stateid = sid
      @seed    = sed
      @racc    = rac
      @ruletable  = rac.ruletable
      @d_reduce   = rac.d_reduce
      @d_shift    = rac.d_shift

      @from_table = {}
      @goto_table = {}

      @lookahead = false

      @rrconf = []
      @srconf = []

      @reduce_ptrs  = []
      @shift_ptrs   = []
      @shift_toks   = []
      @develop_seed = {}

      @ptrs.each do |ptr|
        if ptr.reduce? then
          @reduce_ptrs.push ptr
        else
          @shift_ptrs.push ptr

          tok = ptr.unref
          if tok.term then
            @shift_toks.push tok
          end

          inc = ptr.increment

          if (arr = @develop_seed[ tok ]) then
            arr.push inc
          else
            @develop_seed.store( tok, [ inc ] )
          end
        end
      end
      @shift_toks.uniq!

      if @reduce_ptrs.size > 0 then
        if @ptrs.size == 1 then
          @action = ReduceAction.new( @reduce_ptrs[0] )
        else
          @action = LookaheadAction.new
        end
      else
        @action = ShiftAction.new
      end
    end


    def ==( oth ) @stateid == oth.stateid end

    def eql?( oth ) @seed == oth.seed end

    def stateq( oth ) @stateid == oth.stateid end

    def seedeq( oth ) @seed == oth end

    def hash() @stateid end

    def size() @ptrs.size end

    def to_s() "<LALR state #{@stateid}>" end

    def inspect
      "state #{@stateid}\n" + @ptrs.join("\n")
    end

    def each_ptr
      @ptrs.each{|ptr| yield ptr }
    end


    def is_goto( tok, dest )

      # check infinite recursion
      did = dest.stateid
      if (@stateid == did) and (size < 2) then
        rid = dest.ptrs[0].ruleid
        @racc.logic.push(
          "Infinite recursion: state #{did}, with rule #{rid}" )
      end

      # goto
      @goto_table.store( tok, dest )
    end

    
    def is_from( tok, stat )
      if (temp = @from_table[ tok ]) then
        temp.push stat
      else
        @from_table.store( tok, [ stat ] )
      end
    end


    def resolve_sr

      @shift_toks.each do |stok|
        unless (temp = @action.fetch( stok )) then
          # no conflict
          @action.store( stok, ShiftAction.new )
        else
          if temp.type == ReduceAction then
            # conflict on stok
            rtok = temp.value.prec
            ret = do_resolve_sr( stok, rtok )

            case ret
            when :Reduce
              # action is already set

            when :Shift
              # overwrite
              @action.store( stok, ShiftAction.new )

            when :Remove
              # remove action
              @action.delete( stok )

            when :CantResolve
              # shift to default
              @action.store( stok, ShiftAction.new )
              srconf( stok, temp.value )

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
        @d_reduce and
          puts "resolve_rr: each: state #{@stateid}, #{curptr}"

        la_toks( curptr ).each_key do |tok|
          temp = @action.fetch( tok )
          if ReduceAction === temp then
            #
            # can't resolve R/R conflict (on tok),
            #   reduce with upper rule as default
            #
            rrconf( temp.value, curptr.rule, tok )
          else
            # no conflict
            @action.store( tok, ReduceAction.new( curptr ) )
          end
        end
      end
    end


    def lookahead( idlock )
      @d_reduce and puts "lookahead: state #{@stateid}"

      idlock[ @stateid ] = true         # recurcive lock
      @lookahead and return @lookahead  # cached

      ret  = {}

      temp = []
      @develop_seed.each_key do |tok|
        ret.update tok.first
        if tok.nullp then
          temp.push @goto_table.fetch( tok )
        end
      end
      @reduce_ptrs.each do |ptr|
        temp.concat backtrack( ptr )
      end
      temp.uniq!

      temp.each do |st|
        unless idlock[ st.stateid ] then
          ret.update st.lookahead( idlock )
        end
      end
      @lookahead = ret

      @d_reduce and puts "lookahead: lookahead #{ret.keys.join(' ')}"
      return ret
    end



    private

    
    def do_resolve_sr( stok, rtok )
      @d_shift and
        puts "resolve_sr: s/r conflict: rtok=#{rtok}, stok=#{stok}"

      unless rtok and rtok.prec then
        @d_shift and puts "resolve_sr: no prec for #{rtok}(R)"
        return :CantResolve
      end
      rprec = rtok.prec

      unless stok and stok.prec then
        @d_shift and puts "resolve_sr: no prec for #{stok}(S)"
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

      @d_shift and
        puts "resolve_sr: resolved as #{ret.id2name}"

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
      @d_reduce and
        puts "backtrack: start: state #{@stateid}, ptr #{ptr}"

      sarr = [ self ]
      newstats = []

      until ptr.head? do
        ptr = ptr.decrement
        tok = ptr.unref

        sarr.each do |st|
          (bstats = st.from_table.fetch(tok)) or con_bug!( st, tok )
          newstats.concat bstats
        end
        newstats.uniq!

        sarr.replace newstats
        newstats.clear
      end

      sim = ptr.rule.simbol
      sarr.filter do |st| st.goto_table[ sim ] end

      @d_reduce and
        puts "backtrack: from #{@stateid} to #{sarr2s(sarr)}"

      return sarr
    end

    def sarr2s( sar ) sar.collect{|s| s.stateid}.join(' ') end

    def con_bug!( st, tok )
      bug! "from table void: state #{st.stateid} key #{tok}"
    end


    def rrconf( rule1, rule2, tok )
      @racc.rrconf.push RRconflict.new( @stateid, rule1, rule2, tok )
    end

    def srconf( stok, rrule )
      @racc.srconf.push SRconflict.new( @stateid, stok, rrule )
    end

  end   # LALRstat

  

  class LALRaction
    attr :value
  end

  class ShiftAction < LALRaction
    def initialize() @value = Parser::Shift end
    def to_s()       '<ShiftAction>'        end
  end

  class ReduceAction < LALRaction
    def initialize( ptr ) @value = ptr.rule end
    def to_s()            '<ReduceAction>'  end
  end

  class LookaheadAction < LALRaction
    def initialize()      @value = {}               end
    def each()            @value.each{|t| yield t } end
    def size()            @value.size               end
    def fetch( arg )      @value.fetch( arg )       end
    def store( arg, val ) @value.store( arg, val )  end
    def delete( key )     @value.delete( key )      end
    def to_s()            '<LookaheadAction>'       end
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
