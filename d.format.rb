
  class RaccFormatter


    def initialize( rac )
      @racc = rac
      @ruletable  = rac.ruletable
      @tokentable = @ruletable.tokentable
      @statetable = rac.statetable
      @dsrc       = rac.dsrc

      @temp = {}
    end



    def source
      str = "##### racc generated code begin ###\n"
      acttable_cat( str )
      gototable_cat( str )

      if @dsrc then
        str << "\nDEBUG_PARSER = true\n"
        tostable_cat( str )
      else
        str << "\nDEBUG_PARSER = false\n"
      end

      redumethods_cat( str )
      str << "##### racc generated code end #####\n"

      return str
    end


    def output_state
      str = "\n--------- State ---------\n\n"
      @statetable.each_state do |s|
        cat_state( str, s )
      end
      str << "\n\n"

      return str
    end


    def output_rule
      str = "\n-------- Grammar --------\n\n"
      @ruletable.each_rule do |rl|
        if rl.ruleid == 0 then
          @racc.debug and cat_rule( str, rl )
        else
          cat_rule( str, rl )
        end
      end

      return str
    end


    def output_token
      str = "\n------- Token data -------\n\n"
      cat_toks( str )
      return str
    end



    private


    ########
    ######## .tab.rb
    ########


    def acttable_cat( str )
      str << "LR_action_table = [\n"

      @statetable.each_state do |stat|
        act = stat.action
        sid = stat.stateid

        str << "# state #{sid}\n"
        case act
        when LookaheadAction then laact_cat( str, act )
        when ShiftAction     then str << 'Shift'
        when ReduceAction
          str << ':__reduce_with_rule_'
          str << act.value.ruleid.to_s
        else
          bug! "wrong action #{act.type} in state #{sid}"
        end
        str << ",\n"
      end

      str.chop!
      str.chop!
      str << "\n]   # LR action table\n\n"
    end
      

    def gototable_cat( str )

      str << "LR_goto_table = [\n"
      @statetable.each_state do |stat|
        sid = stat.stateid
        tbl = stat.goto_table
        
        str << "# state #{sid}\n"
        if tbl.size == 0 then
          str << "nil,\n"
        else
          str << "{\n"
          tbl.each do |tok, dest|
            str << (tok.conv or tok.uneval)
            str << ' => '
            str << dest.stateid.to_s

            str << ",\n"
          end
          str.chop!
          str.chop!
          str << "\n},\n"
        end
      end
      str.chop!
      str.chop!
      str << "\n]   # LR goto table\n"
    end


    def redumethods_cat( str )

      @ruletable.each_rule do |rl|
        le = (rl.size * -1).to_s << ', '
        le << rl.size.to_s

        str.concat <<SOURCE

def __reduce_with_rule_#{rl.ruleid}( vstack, sstack, __state__ )
 val = vstack[ #{le} ]
 sim = sstack[ #{le} ]
SOURCE

        if @dsrc then
          str << %| if @__debug__ then\n|

          if rl.size == 0 then
            str << %|   print '<none>'\n|
          else
            idx = 0
            rl.each_token do |tok|
              str << %|   print ' #{tok}', "(\#{val[#{idx}].inspect})"\n|
              idx += 1
            end
          end

          str << %|   print ' --> ', '| << rl.simbol.to_s << %|'\n|
          str << %|   print "\\n"\n|
          str << %| end\n|
        end

        if rl.accept? then
          sim = 'Accept'
        else
          sim = rl.simbol.uneval
        end

        str.concat <<SOURCE
 vstack[ #{le} ] = []
 sstack[ #{le} ] = []
 sstack.push #{sim}
 __state__[ #{le} ] = []
 result = val[0]
 #{rl.action}
 return result
end
SOURCE
      end
    end


    def laact_cat( str, act )
      val = act.value
      val.size == 0 and bug! "LA action size is 0"

      str << "{\n"
      val.each do |tok, act|
        str << (tok.conv or tok.uneval) << ' => '
        case act
        when ShiftAction
          str << 'Shift'
        when ReduceAction
          str << ':__reduce_with_rule_' << act.value.ruleid.to_s
        end
        str << ",\n"
      end
      str.chop!
      str.chop!
      str << "\n}"

      return str
    end


    def tostable_cat( str )
      str << "\nTOKEN_TO_S_TABLE = {"
      term = "\n"
      first = true
      @tokentable.each_token do |tok|
        str << term << (tok.conv or tok.uneval)
        str << " => '" << tok.to_s
        if first then
          first = false
          term = "',\n"
        end
      end
      str << "'\n}\n"
    end


    #########
    #########  .output
    #########


    def cat_state( str, stat )
      str << sprintf( "state %d\n\n", stat.stateid )

      stat.ptrs.each do |pt| cat_ptr( str, pt ) end
      str << "\n"

      act = stat.action
      case act
      when LookaheadAction then cat_laact( str, stat )
      when ShiftAction     then cat_shift( str, stat )
      when ReduceAction    then cat_reduce( str, stat )
      else
        bug! "cat_state not match: act=#{act}(#{act.type})"
      end
      str << "\n\n"
    end


    def cat_ptr( str, ptr )
      rule = ptr.rule

      str << "#{rule.ruleid.to_s.rjust(4)}) "

      str << rule.simbol.to_s << ' :'

      temp = 0
      rule.each_token do |tok|
        if temp == ptr.index then str << ' _' end
        str << ' ' << tok.to_s
        temp += 1
      end

      if ptr.reduce? then
        str << ' _'
      end
      str << "\n"
    end


    def cat_laact( str, stat )
      action = stat.action
      tstr = ''
      nstr = ''

      action.each do |tok, act|
        case act
        when ShiftAction  then cat_termline( tstr, tok, stat.goto_table[tok] )
        when ReduceAction then cat_lareduce( str, tok, act )
        else
          bug! "cat_laact not match: act=#{act}(#{act.type})"
        end
      end

      str << tstr
      first = true

      stat.goto_table.each do |tok, dest|
        unless tok.term then
          if first then
            str << "\n"
            first = false
          end

          temp = stat.goto_table[ tok ]
          cat_ntermline( str, tok, temp )
        end
      end
    end


    def cat_shift( str, stat )
      act = stat.action
      gstr = ''
      ssize = 0
      gsize = 0

      stat.goto_table.each do |tok,stat|
        if tok.term then
          cat_termline( str, tok, stat )
          ssize += 1
        else
          cat_ntermline( gstr, tok, stat )
          gsize += 1
        end
      end

      if gsize > 0 then
        if ssize > 0 then str << "\n" end
        str << gstr
      end
    end


    def cat_termline( str, tok, stat )
      str << sprintf(
        "  %-12s  shift, and go to state %d\n", 
        tok.to_s,
        stat.stateid
      )
    end


    def cat_ntermline( str, tok, stat )
      str << sprintf(
        "  %-12s  go to state %d\n", 
        tok.to_s,
        stat.stateid
      )
    end


    def cat_reduce( str, stat )
      rule = stat.action.value
      if rule.accept? then
        str << "  accept\n"
      else
        str << sprintf( "  reduce using rule %d\n", rule.ruleid )
      end
    end


    def cat_lareduce( str, tok, act )
      rule = act.value
      if rule.accept? then
        str << sprintf( "  %-12s  accept\n", tok.to_s )
      else
        str << sprintf(
          "  %-12s  reduce using rule %d\n",
          tok.to_s,
          rule.ruleid
        )
      end
    end


    def cat_toks( str )
      str << "**Terminals, with rules where they appear\n\n"
      nstr = "\n**Nonterminals, with rules where they appear\n\n"

      @tokentable.each_token do |tok|
        if tok.term then
          unless tok.anchor? then
            cat_termtok( str, tok )
          end
        else
          unless tok.dammy? then
            cat_ntermtok( nstr, tok )
          end
        end
      end

      str << nstr
    end


    def cat_termtok( str, tok )
      str << '  ' << tok.to_s
      (temp = tok.conv) and str << "(#{temp})"
      str << "\n"

      # locate
      str << '    on right: ' << arr2strnz( tok.locate ) << "\n\n"
    end


    def cat_ntermtok( str, tok )
      str << '  ' << tok.to_s << "\n"

      # locate
      if tok.locate.size > 0 then
        str << '    on right: ' << arr2strnz( tok.locate ) << "\n"
      end

      # rule
      str << '    on left : ' << arr2strnz( tok.rules ) << "\n\n"
    end


    def cat_rule( str, rl )
      str << 'rule ' << rl.ruleid.to_s.ljust(5) << ' '
      str << rl.simbol.to_s << ':'
      rl.each_token{|tok| str << ' ' << tok.to_s}
      str << "\n\n"
    end

    
    def arr2strnz( arr )
      arr.each do |ptr|
        @temp.store( ptr.ruleid, true ) unless ptr.ruleid == 0
      end
      ret = @temp.keys.join(' ')
      @temp.clear

      return ret
    end

  end

