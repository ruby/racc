
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
      main_table_cat( str )

      if @dsrc then
        str << "\nDEBUG_PARSER = true\n"
        tostable_cat( str )
      else
        str << "\nDEBUG_PARSER = false\n"
      end

      reduce_method_all_cat( str )
      str << "##### racc generated code end #####\n"

      return str
    end


    def output_state
      str = "\n--------- State ---------\n\n"
      @statetable.each_state{|s| cat_state( str, s ) }
      str << "\n\n"

      return str
    end


    def output_rule
      str = "\n-------- Grammar --------\n\n"
      @ruletable.each_rule do |rl|
        cat_rule( str, rl ) if @racc.debug or rl.ruleid != 0
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


    def main_table_cat( str )
      str << 'LR_action_table = ['
      sep = "\n"

      @statetable.each_state do |state|
        act = state.action

        str << sep ; sep = ",\n"
        str << "# state #{state.stateid}\n"

        case act
        when LookaheadAction then laact_cat( str, act )
        when ShiftAction     then str << 'Shift'
        when ReduceAction
          str << ":__reduce_with_rule_#{act.value.ruleid}"
        else
          bug! "wrong action #{act.type} in state #{state.stateid}"
        end
      end
      str << "\n]   # LR action table\n\n"
    end
      

    def gototable_cat( str )
      str << 'LR_goto_table = ['
      com = "\n"

      @statetable.each_state do |state|
        str << com ; com = ",\n"
        str << "# state #{state.stateid}\n"

        if state.goto_table.size == 0 then
          str << 'nil'
        else
          str << '{'
          add = "\n"

          state.goto_table.each do |tok, dest|
            str << "#{add}#{tok.conv or tok.uneval} => #{dest.stateid}"
            add = ",\n"
          end
          str << "\n}"
        end
      end
      str << "\n]   # LR goto table\n"
    end


    def reduce_method_all_cat( str )
      @ruletable.each_rule do |rl|
        reduce_method_cat( str, rl )
      end
    end

 sstack.push #{rl.accept? ? 'Accept' : rl.simbol.uneval}

    def reduce_method_cat( str, rl )
      le = (rl.size * -1).to_s << ', '
      le << rl.size.to_s

      str.concat <<SOURCE

def __reduce_with_rule_#{rl.ruleid}( tok, val, tokens, values, __state__ )
SOURCE

      if @dsrc then
        str <<   %| if @__debug__ then\n|
        idx = 0
        if rl.size == 0 then
          str <<   %|  print ' <none>'\n|
        else
          rl.each_token do |tok|
            str << %|  print " #{tok}(\#{val[#{idx}].inspect})"\n|
            idx += 1
          end
        end
        str <<   %|  print " --> #{rl.simbol.to_s}\\n"\n|
        str <<   %| end\n|
      end

      str.concat <<SOURCE
 result = val[0]
 #{rl.action}
 result
end
SOURCE
    end


    def laact_cat( str, act )
      if act.value.size == 0 then
        bug! "LA action size is 0"
      end

      str << '{'
      com = "\n"
      act.value.each do |tok, act|
        str << com ; com = ",\n"
        str << "#{tok.conv or tok.uneval} => "
        case act
        when ShiftAction  then str << 'Shift'
        when ReduceAction then str << ":__reduce_with_rule_#{act.value.ruleid}"
        end
      end
      str << "\n}"
      str
    end


    def tostable_cat( str )
      str << "\nTOKEN_TO_S_TABLE = {"
      com = "\n"
      @tokentable.each_token do |tok|
        str << com ; com = ",\n"
        str << "#{tok.conv or tok.uneval} => '#{tok}'"
      end
      str << "\n}\n"
    end


    #########
    #########  .output
    #########


    def cat_state( str, state )
      str << "state #{state.stateid}\n"

      state.ptrs.each{|pt| cat_ptr( str, pt ) }
      str << "\n"

      act = state.action
      case act
      when LookaheadAction then cat_laact( str, state )
      when ShiftAction     then cat_shift( str, state )
      when ReduceAction    then cat_reduce( str, state )
      else
        bug! "cat_state not match: act=#{act}(#{act.type})"
      end
      str << "\n\n"
    end


    def cat_ptr( str, ptr )
      rule = ptr.rule

      str << "#{rule.ruleid.to_s.rjust(4)}) #{rule.simbol} :"

      rule.each_token_with_index do |tok, idx|
        str << ' _' if idx == ptr.index
        str << " #{tok}"
      end
      if ptr.reduce? then
        str << ' _'
      end
      str << "\n"
    end


    def cat_laact( str, state )
      tstr = ''
      nstr = ''

      state.action.each do |tok, act|
        case act
        when ShiftAction  then cat_termline( tstr, tok, state.goto_table[tok] )
        when ReduceAction then cat_lareduce( str, tok, act )
        else
          bug! "cat_laact not match: act=#{act}(#{act.type})"
        end
      end
      str << tstr

      state.goto_table.each do |tok, dest|
        com = "\n"
        unless tok.term then
          str << com ; com = ''
          cat_ntermline( str, tok, state.goto_table[tok] )
        end
      end
    end


    def cat_shift( str, state )
      act = state.action
      gstr = ''
      ssize = 0
      gsize = 0

      state.goto_table.each do |tok,state|
        if tok.term then cat_termline( str, tok, state )   ; ssize += 1
        else             cat_ntermline( gstr, tok, state ) ; gsize += 1
        end
      end

      if gsize > 0 then
        str << "\n" if ssize > 0
        str << gstr
      end
    end


    def cat_termline( str, tok, state )
      str << sprintf( "  %-12s  shift, and go to state %d\n", 
                      tok.to_s, state.stateid )
    end


    def cat_ntermline( str, tok, state )
      str << sprintf( "  %-12s  go to state %d\n", 
                      tok.to_s, state.stateid )
    end


    def cat_reduce( str, state )
      rule = state.action.value
      if rule.accept? then str << "  accept\n"
      else                 str << "  reduce using rule #{rule.ruleid}\n"
      end
    end


    def cat_lareduce( str, tok, act )
      rule = act.value
      if rule.accept? then str << sprintf( "  %-12s  accept\n", tok.to_s )
      else                 str << sprintf( "  %-12s  reduce using rule %d\n",
                                           tok.to_s, rule.ruleid )
      end
    end


    def cat_toks( str )
      str << "**Terminals, with rules where they appear\n\n"
      nstr = "\n**Nonterminals, with rules where they appear\n\n"

      @tokentable.each_token do |tok|
        if tok.term then cat_termtok( str, tok ) unless tok.anchor?
        else             cat_ntermtok( nstr, tok ) unless tok.dammy?
        end
      end

      str << nstr
    end


    def cat_termtok( str, tok )
      str << "  #{tok}"
      if temp = tok.conv then str << "(#{temp})" end
      str << "\n"

      # locate
      str << "    on right: #{arr2strnz(tok.locate)}\n\n"
    end


    def cat_ntermtok( str, tok )
      str << "  #{tok}\n"

      # locate
      if tok.locate.size > 0 then
        str << "    on right: #{arr2strnz(tok.locate)}\n"
      end

      # rule
      str << "    on left : #{arr2strnz(tok.rules)}\n\n"
    end


    def cat_rule( str, rl )
      str << sprintf( 'rule %-5d %s:',
                      rl.ruleid, rl.simbol.to_s )
      rl.each_token{|tok| str << " #{tok}" }
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

