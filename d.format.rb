
  class RaccFormatter

    def initialize( racc )
      @ruletable  = racc.ruletable
      @tokentable = racc.tokentable
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
      out << "\n"
      goto_table_tab( out )
      out << "\n"
      token_table_tab( out )
      if @dsrc then
        out << "\nDEBUG_PARSER = true\n"
        out << "\nTOKEN_TO_S_TABLE = [\n"
        out << @tokentable.collect{|tok| "'" + tok.to_s + "'" }.join(",\n")
        out << "]\n"
      else
        out << "\nDEBUG_PARSER = false\n"
      end
      reduce_methods_tab( out )

      out << "##### racc generated code end #####\n"
    end


    #####


    def action_table_tab( out )
      #
      # actions
      #

      shift_n = ShiftAction::Instance.size
      out << "\nLR_shift_n = #{shift_n}\n\n"

      sep = "\n"
      sep_rest = ",\n"
      out << "LR_reduce_table = [\n"
      out << "0, 0, :racc_error,"
      @ruletable.each_with_index do |rl, i|
        next if i == 0
        out << sep; sep = sep_rest
        out << sprintf( "%d, %d, :_reduce_%d",
                        rl.size, rl.simbol.tokenid, i )
      end
      out << " ]\n\n"
      reduce_n = @ruletable.size
      out << "LR_reduce_n = #{reduce_n}\n\n"

      acc = -1 - reduce_n
      err = shift_n + 1

      #
      # tables
      #

      deft = @tokentable.default
      defact = nil
      disc = []
      tbl = []

      @statetable.each_state do |state|
        disc.push tbl.size
        state.action.each do |tok, act|
          n = case act
              when ShiftAction  then act.goto_state
              when ReduceAction then -act.rule.ruleid
              when AcceptAction then acc
              when ErrorAction  then err
              else
                bug! "wrong act type #{act.type} in state #{state.stateid}"
              end
          if tok == deft then
            defact = n
          else
            tbl.push tok.tokenid
            tbl.push n
          end
        end
        tbl.push Token::Default
        tbl.push defact
      end

      out << "LR_action_table = [\n"
      table_tab( out, tbl )

      out << "LR_action_table_ptr = [\n"
      table_tab( out, disc )
    end
      

    def goto_table_tab( out )
      disc = []
      tbl = []
      @statetable.each_state do |state|
        if state.nonterm_table.size == 0 then
          disc.push -1
        else
          disc.push tbl.size
          state.nonterm_table.each do |tok, dest|
            tbl.push tok.tokenid
            tbl.push dest.stateid
          end
        end
      end
      out << "LR_goto_table = [\n"
      table_tab( out, tbl )

      out << "LR_goto_table_ptr = [\n"
      table_tab( out, disc )
    end


    def table_tab( out, arr )
      i = 0
      sep = ''
      sep_rest = ','
      buf = ''

      arr.each do |t|
        buf << sep ; sep = sep_rest
        if i == 10 then
          i = 0
          out << buf << "\n"
          buf = ''
        end
        buf << sprintf('%6d', t)
        i += 1
      end
      out << buf unless buf.empty?
      out << " ]\n\n"
    end


    def token_table_tab( out )
      sep = "\n"
      sep_rest = ",\n"
      out << "LR_token_table = {"
      @tokentable.each do |tok|
        if tok.terminal? then
          out << sep ; sep = sep_rest
          out << sprintf( " %s => %d", tok.uneval, tok.tokenid )
        end
      end
      out << " }\n"
    end


    def reduce_methods_tab( out )
      @ruletable.each_rule do |rl|
        rl.action.sub! /\A\s*(\n|\r\n|\r)/o, ''
        rl.action.sub! /\s+\z/o, ''
        out << sprintf( <<SOURCE, rl.ruleid, rl.action )

def _reduce_%d( tok, val, _tokens, _values, _states )
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
      out << "\n--------- State ---------\n"

      @statetable.each_state do |state|
        out << "\nstate #{state.stateid}\n\n"

        state.seed.each do |ptr|
          pointer_out( out, ptr ) if ptr.rule.ruleid != 0
        end
        out << "\n"

        action_out( out, state )
      end

      return out
    end


    def pointer_out( out, ptr )
      tmp = sprintf( "%4d) %s :",
                     ptr.rule.ruleid, ptr.rule.simbol.to_s )
      ptr.rule.each_with_index do |tok, idx|
        tmp << ' _' if idx == ptr.index
        tmp << ' ' << tok.to_s
      end
      tmp << ' _' if ptr.reduce?
      tmp << "\n"
      out << tmp
    end


    def action_out( out, state )
      reduce_str = ''

      state.action.each do |tok, act|
        case act
        when ShiftAction
          out << sprintf( "  %-12s  shift, and go to state %d\n", 
                          tok.to_s, act.goto_state )
        when ReduceAction
          reduce_str << sprintf( "  %-12s  reduce using rule %d\n",
                                 tok.to_s, act.rule.ruleid )
        when AcceptAction
          out << sprintf( "  %-12s  accept\n", tok.to_s )
        when ErrorAction
          # out << sprintf( "  %-12s  error\n", tok.to_s )
        else
          bug! "act is not shift/reduce/accept: act=#{act}(#{act.type})"
        end
      end
      out << reduce_str
      out << "\n"

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

      @tokentable.each do |tok|
        if tok.terminal? then
          terminal_out( tmp, tok ) # unless tok.anchor?
        else
          nonterminal_out( out, tok ) # unless tok.dummy?
        end
      end

      out << "\n" << tmp

      return out
    end


    def terminal_out( out, tok )
      tmp = <<SRC
  %s (%d) %s

SRC
      out << sprintf( tmp, tok.to_s, tok.tokenid, tokens2s( tok.locate ) )
    end


    def nonterminal_out( out, tok )
      tmp = <<SRC
  %s (%d)
    on right: %s
    on left : %s
SRC
      out << sprintf( tmp, tok.to_s, tok.tokenid,
                      tokens2s( tok.locate ), tokens2s( tok.rules ) )
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

