
  class RaccFormatter

    def initialize( racc )
      @ruletable  = racc.ruletable
      @statetable = racc.statetable
      @dsrc       = racc.dsrc
      @debug      = racc.debug

      @hash = {}
    end


    ########
    ######## .tab.rb
    ########


    def source( out = '' )
      out << "##### racc generated code begin ###\n\n"

      action_table_tab( out )
      goto_table_tab( out )
      if @dsrc then
        out << "\nDEBUG_PARSER = true\n"
        out << "\nTOKEN_TO_S_TABLE = {\n"
        out << Token::Instance.collect{|v,tok|
               sprintf( "%s => '%s'", tok.uneval, tok.to_s ) }.join(",\n")
        out << "\n}\n"
      else
        out << "\nDEBUG_PARSER = false\n"
      end
      reduce_methods_tab( out )

      out << "##### racc generated code end #####\n"
    end


    #####


    def action_table_tab( out )

      ShiftAction.each_instance do |obj|
        i = obj.goto_state
        out << "shift_#{i} = #{i}\n"
      end
      out << "\n"

      @ruletable.each_with_index do |rl, i|
        out <<
          sprintf( "reduce_%d = [%d, %s, :_action_for_reduce_%d]\n",
            i, rl.size, rl.accept? ? 'Accept' : rl.simbol.uneval, i )
      end
      out << "\n"

      out << 'LR_action_table = ['
      sep = "\n"

      @statetable.each_state do |state|

        out << sep ; sep = ",\n"
        out << "# state #{state.stateid}\n{"

        comma = " "
        state.action.each do |tok, act|
          out << comma ; comma = ",\n  "
          out << tok.uneval << ' => ' <<
            case act
            when ShiftAction  then "shift_#{act.goto_state}"
            when ReduceAction then "reduce_#{act.rule.ruleid}"
            else
              bug! "wrong act type #{act.type} in state #{state.stateid}"
            end
        end
        out << " }"
      end
      out << "\n]   # LR action table\n\n"
    end
      

    def goto_table_tab( out )
      out << 'LR_goto_table = ['
      sep = "\n"

      @statetable.each_state do |state|
        out << sep ; sep = ",\n"
        out << "# state #{state.stateid}\n"

        if state.nonterm_table.size == 0 then
          out << 'nil'
        else
          out << "{ " << state.nonterm_table.collect{|tok, dest|
            tok.uneval + ' => ' + dest.stateid.to_s }.join(",\n  ")
          out << ' }'
        end
      end
      out << "\n]   # LR goto table\n"
    end


    def reduce_methods_tab( out )
      @ruletable.each_rule do |rl|
        out << sprintf( <<SOURCE, rl.ruleid, rl.action )

def _action_for_reduce_%d( tok, val, _tokens, _values, _states )
 result = val[0]
%s
 result
end
SOURCE
      end
    end


    #########
    #########  .output
    #########


    def output_state( out )
      out << "\n--------- State ---------\n\n"

      @statetable.each_state do |state|
        out << "state #{state.stateid}\n"

        state.closure.each {|ptr| pointer_out( out, ptr ) }
        out << "\n"

        action_out( out, state )
        out << "\n\n"
      end
      out << "\n\n"

      return out
    end


    def pointer_out( out, ptr )
      tmp = ''
      ptr.rule.each_with_index do |tok, idx|
        tmp << ' _' if idx == ptr.index
        tmp << ' ' << tok.to_s
      end
      tmp << ' _' if ptr.reduce?

      out << sprintf( "%4d) %s :%s\n",
                      ptr.rule.ruleid, ptr.rule.simbol.to_s, tmp )
    end


    def action_out( out, state )
      shift_str = ''

      state.action.each do |tok, act|
        case act
        when ShiftAction
          shift_str << sprintf( "  %-12s  shift, and go to state %d\n", 
                                tok.to_s, act.goto_state )
        when ReduceAction
          out <<
            if   act.rule.accept?
            then sprintf( "  %-12s  accept\n", tok.to_s )
            else sprintf( "  %-12s  reduce using rule %d\n",
                          tok.to_s, act.rule.ruleid )
            end
        else
          bug! "act is not shift/reduce: act=#{act}(#{act.type})"
        end
      end
      out << shift_str

      state.nonterm_table.each do |tok, dest|
        out << sprintf( "  %-12s  go to state %d\n", 
                        tok.to_s, state.stateid )
      end
    end


    #####


    def output_rule( out )
      out << "\n-------- Grammar --------\n\n"
      @ruletable.each_rule do |rl|
        if @debug or rl.ruleid != 0 then
          out << sprintf( "rule %d %s: %s\n\n",
            rl.ruleid, rl.simbol.to_s, rl.tokens.join(' ') )
        end
      end

      return out
    end


    #####


    def output_token( out )
      out << "\n------- Token data -------\n\n"

      out << "**Nonterminals, with rules where they appear\n\n"
      tmp = "**Terminals, with rules where they appear\n\n"

      Token.each do |tok|
        if tok.terminal? then
          terminal_out( tmp, tok ) unless tok.anchor?
        else
          nonterminal_out( out, tok ) unless tok.dammy?
        end
      end

      out << "\n" << tmp

      return out
    end


    def terminal_out( out, tok )
      tmp = <<SRC
  %s%s
    on right: %s

SRC
      out << sprintf( tmp,
        tok.to_s, tok.conv || '', tokens2s( tok.locate ) )
    end


    def nonterminal_out( out, tok )
      tmp = <<SRC
  %s
    on right: %s
    on left : %s
SRC
      out << sprintf( tmp,
        tok.to_s, tokens2s( tok.locate ), tokens2s( tok.rules ) )
    end

    
    def tokens2s( arr )
      arr.each do |ptr|
        @hash[ ptr.ruleid ] = true if ptr.ruleid != 0
      end
      ret = @hash.keys.join(' ')
      @hash.clear

      return ret
    end

  end   # class RaccFormatter

