#
# format.rb
#
#   Copyright (c) 1999,2000 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#
#   This program is free software.
#   You can distribute/modify this program under the terms of
#   the GNU Lesser General Public License version 2 or later.
#

require 'amstd/bug'


module Racc

  class RaccFormatter

    def initialize( racc )
      @ruletable  = racc.ruletable
      @tokentable = racc.tokentable
      @statetable = racc.statetable
      @actions    = racc.statetable.actions
      @parser     = racc.parser
      @dsrc       = racc.dsrc
      @debug      = racc.debug
      @verbose    = racc.d_verbose
      @line       = racc.d_line
    end

    # abstract output( outf )
  
  end


  class RaccCodeGenerator < RaccFormatter

    def output( out )
      out << "##### racc #{Racc::Version} generates ###\n\n"

      output_reduce_table out
      output_action_table out
      output_goto_table out
      output_token_table out
      output_other out
      if @dsrc then
        out << "Racc_debug_parser = true\n\n"
        out << "Racc_token_to_s_table = [\n"
        out << @tokentable.collect{|tok| "'" + tok.to_s + "'" }.join(",\n")
        out << "]\n\n"
      else
        out << "Racc_debug_parser = false\n\n"
      end
      out << "##### racc system variables end #####\n\n"

      output_actions out
      out << "\n"
    end


    private

    def act2actid( act )
      case act
      when ShiftAction  then act.goto_id
      when ReduceAction then -act.ruleid
      when AcceptAction then @actions.shift_n
      when ErrorAction  then @actions.reduce_n * -1
      else
        bug! "wrong act type #{act.type} in state #{state.stateid}"
      end
    end

    def output_table( out, arr )
      i = 0
      sep = ''
      sep_rest = ','
      buf = ''

      arr.each do |t|
        buf << sep ; sep = sep_rest
        if i == 10 then
          i = 0
          buf << "\n"
          out << buf
          buf = ''
        end
        buf << (t ? sprintf('%6d', t) : '   nil')
        i += 1
      end
      out << buf unless buf.empty?
      out << " ]\n\n"
    end


    def output_reduce_table( out )
      out << "racc_reduce_table = [\n"
      out << " 0, 0, :racc_error,"
      sep = "\n"
      sep_rest = ",\n"
      @ruletable.each_with_index do |rl, i|
        next if i == 0
        out << sep; sep = sep_rest
        out << sprintf( ' %d, %d, :_reduce_%s',
                        rl.size,
                        rl.symbol.tokenid,
                        rl.action ? i.to_s : 'none' )
      end
      out << " ]\n\n"
      out << "racc_reduce_n = #{@actions.reduce_n}\n\n"
      out << "racc_shift_n = #{@actions.shift_n}\n\n"
    end

    def output_token_table( out )
      sep = "\n"
      sep_rest = ",\n"
      out << "racc_token_table = {"
      @tokentable.each do |tok|
        if tok.terminal? then
          out << sep ; sep = sep_rest
          out << sprintf( " %s => %d", tok.uneval, tok.tokenid )
        end
      end
      out << " }\n\n"
    end

    def output_actions( out )
      line = @line

      @ruletable.each_rule do |rl|
        if str = rl.action then
          i = rl.lineno
          while /\A[ \t\f]*(?:\n|\r\n|\r)/ === str do
            str = $'
            i += 1
          end
          str.sub! /\s+\z/o, ''
          if line then
            out << sprintf( <<SOURCE, @parser.filename, i - 1, rl.ident, str )

 module_eval( <<'.,.,', '%s', %d )
  def _reduce_%d( val, _values, result )
%s
   result
  end
.,.,
SOURCE
          else
            out << sprintf( <<SOURCE, rl.ident, str )

  def _reduce_%d( val, _values, result )
%s
   result
  end
SOURCE
          end
        else
          out << sprintf( "\n # reduce %d omitted\n",
                          rl.ident )
        end
      end
    end

  end


  class AListTableGenerator < RaccCodeGenerator

    private

    def output_action_table( out )
      $stderr.puts 'generating action table (type a)' if @verbose

      disc = []
      tbl = []

      @statetable.each_state do |state|
        disc.push tbl.size
        state.action.each do |tok, act|
          tbl.push tok.tokenid
          tbl.push act2actid( act )
        end
        tbl.push Token::Default_token_id
        tbl.push act2actid( state.defact )
      end

      out << "racc_action_table = [\n"
      output_table( out, tbl )

      out << "racc_action_pointer = [\n"
      output_table( out, disc )
    end


    def output_goto_table( out )
      $stderr.puts 'generating goto table (type a)' if @verbose

      disc = []
      tbl = []
      @statetable.each_state do |state|
        if state.nonterm_table.size == 0 then
          disc.push( -1 )
        else
          disc.push tbl.size
          state.nonterm_table.each do |tok, dest|
            tbl.push tok.tokenid
            tbl.push dest.stateid
          end
        end
      end
      tbl.push( -1 ); tbl.push( -1 )   # detect bug

      out << "racc_goto_table = [\n"
      output_table( out, tbl )

      out << "racc_goto_pointer = [\n"
      output_table( out, disc )
    end

    def output_other( out )
      out << <<S
Racc_arg = [
 racc_action_table,
 racc_action_pointer,
 racc_goto_table,
 racc_goto_pointer,
 racc_reduce_table,
 racc_token_table,
 racc_shift_n,
 racc_reduce_n ]

S
    end

  end


  class IndexTableGenerator < RaccCodeGenerator
  
    private

    def output_action_table( out )
      $stderr.puts 'generating action table (type i)' if @verbose

      tbl  = []   # yytable
      chk  = []   # yycheck
      defa = []   # yydefact
      ptr  = []   # yypact
      state = tmp = min = max = i = nil
      e1 = []
      e2 = []

      @statetable.each_state do |state|
        # default
        defa.push act2actid( state.defact )

        if state.action.empty? then
          ptr.push nil
          next
        end

        tmp = []
        state.action.each do |tok, act|
          tmp[ tok.tokenid ] = act2actid( act )
        end

        addent( e1, e2, tmp, state.stateid, ptr )
      end
      set_table e1, e2, tbl, chk, ptr

      out << "racc_action_table = [\n"
      output_table( out, tbl )

      out << "racc_action_check = [\n"
      output_table( out, chk )

      out << "racc_action_default = [\n"
      output_table( out, defa )

      out << "racc_action_pointer = [\n"
      output_table( out, ptr )
    end


    def output_goto_table( out )
      $stderr.puts 'generating goto table (type i)' if @verbose

      tbl  = []   # yytable (2)
      chk  = []   # yycheck (2)
      ptr  = []   # yypgoto
      defg = []   # yydefgoto
      state = dflt = tmp = freq = min = max = i = nil
      e1 = []
      e2 = []

      @tokentable.each_nonterm do |tok|
        tmp = []

        #
        # decide default
        #
        freq = Array.new( @statetable.size, 0 )
        @statetable.each_state do |state|
          st = state.goto_table[ tok ]
          if st then
            st = st.stateid
            freq[ st ] += 1
          end
          tmp[ state.stateid ] = st
        end
        max = freq.max
        if max > 1 then
          dflt = freq.index( max )
          tmp.collect! {|i| dflt == i ? nil : i }
        else
          dflt = nil
        end

        # default
        defg.push dflt

        #
        # delete default value
        #
        tmp.delete_at(-1) until tmp[-1] or tmp.empty?
        if tmp.compact.empty? then
          # only default
          ptr.push nil
          next
        end

        addent( e1, e2, tmp, tok.tokenid - @tokentable.nt_base, ptr )
      end
      set_table e1, e2, tbl, chk, ptr

      out << "racc_goto_table = [\n"
      output_table( out, tbl )

      out << "racc_goto_check = [\n"
      output_table( out, chk )

      out << "racc_goto_pointer = [\n"
      output_table( out, ptr )

      out << "racc_goto_default = [\n"
      output_table( out, defg )
    end

    def addent( all, dummy, arr, chkval, ptr )
      max = arr.size
      min = nil
      item = idx = nil
      arr.each_with_index do |item,idx|
        if item then
          min ||= idx
        end
      end
      ptr.push( -7777 )    # mark

      arr = arr[ min, max - min ]
      ent = [ arr, chkval, mkmapexp(arr), min, ptr.size - 1 ]
      all.push ent
    end

    def mkmapexp( arr )
      i = ii = 0
      as = arr.size
      map = ''
      while i < as do
        ii = i + 1
        if arr[i] then
          ii += 1 while ii < as and arr[ii]
          map << '-'
        else
          ii += 1 while ii < as and not arr[ii]
          map << '.'
        end
        map << "{#{ii - i}}" if ii - i > 1
        i = ii
      end

      Regexp.new( map, 'n' )
    end

    def set_table( entries, dummy, tbl, chk, ptr )
      a = b = ent = nil
      idx = item = i = nil
      arr = chkval = min = ptri = exp = nil
      upper = 0
      map = '-' * 10240

      # sort long to short
      entries.sort! {|a,b| b[0].size <=> a[0].size }

      entries.each do |ent|
        arr, chkval, exp, min, ptri = *ent

        if upper + arr.size > map.size then
          map << '-' * (arr.size + 1024)
        end
        idx = map.index( exp )
        ptr[ ptri ] = idx - min
        arr.each_with_index do |item, i|
          if item then
            i += idx
            tbl[i] = item
            chk[i] = chkval
            map[i] = ?o
          end
        end
        upper = idx + arr.size
      end
    end


    def output_other( out )
      out << <<S
racc_nt_base = #{@tokentable.nt_base}

Racc_arg = [
 racc_action_table,
 racc_action_check,
 racc_action_default,
 racc_action_pointer,
 racc_goto_table,
 racc_goto_check,
 racc_goto_default,
 racc_goto_pointer,
 racc_nt_base,
 racc_reduce_table,
 racc_token_table,
 racc_shift_n,
 racc_reduce_n ]

S
    end

  end


  ###
  ###
  ###

  class VerboseOutputFormatter < RaccFormatter

    def output( out )
      output_conflict out; out << "\n"
      output_useless  out; out << "\n"
      output_rule     out; out << "\n"
      output_token    out; out << "\n"
      output_state    out
    end


    def output_conflict( out )
      @statetable.each_state do |state|
        if state.srconf then
          out << sprintf( "state %d contains %d shift/reduce conflicts\n",
                          state.stateid, state.srconf.size )
        end
        if state.rrconf then
          out << sprintf( "state %d contains %d reduce/reduce conflicts\n",
                          state.stateid, state.rrconf.size )
        end
      end
    end


    def output_useless( out )
      rl = t = nil
      used = []
      @ruletable.each do |rl|
        if rl.useless? then
          out << sprintf( "rule %d (%s) never reduced\n",
                          rl.ident, rl.symbol.to_s )
        end
      end
      @tokentable.each_nonterm do |t|
        if t.useless? then
          out << sprintf( "useless nonterminal %s\n",
                          t.to_s )
        end
      end
    end


    def output_state( out )
      ptr = nil
      out << "--------- State ---------\n"

      @statetable.each_state do |state|
        out << "\nstate #{state.stateid}\n\n"

        state.core.each do |ptr|
          pointer_out( out, ptr ) if ptr.rule.ident != 0 or @debug
        end
        out << "\n"

        action_out( out, state )
      end

      return out
    end

    def pointer_out( out, ptr )
      tmp = sprintf( "%4d) %s :",
                     ptr.rule.ident, ptr.rule.symbol.to_s )
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

      srconf = state.srconf and state.srconf.dup
      rrconf = state.rrconf and state.rrconf.dup

      state.action.each do |tok, act|
        outact out, reduce_str, tok, act
        if srconf and c = srconf.delete(tok) then
          outsrconf reduce_str, c
        end
        if rrconf and c = rrconf.delete(tok) then
          outrrconf reduce_str, c
        end
      end
      if srconf and not srconf.empty? then
        srconf.each do |tok, c|
          outsrconf reduce_str, c
        end
      end
      if rrconf and not rrconf.empty? then
        rrconf.each do |tok, c|
          outrrconf reduce_str, c
        end
      end
      outact out, reduce_str, '$default', state.defact

      out << reduce_str
      out << "\n"

      state.goto_table.each do |tok, dest|
        out << sprintf( "  %-12s  go to state %d\n", 
                        tok.to_s, dest.stateid ) unless tok.terminal?
      end
    end

    def outact( out, r, tok, act )
      case act
      when ShiftAction
        out << sprintf( "  %-12s  shift, and go to state %d\n", 
                        tok.to_s, act.goto_id )
      when ReduceAction
        r << sprintf( "  %-12s  reduce using rule %d (%s)\n",
                      tok.to_s, act.ruleid, act.rule.symbol.to_s )
      when AcceptAction
        out << sprintf( "  %-12s  accept\n", tok.to_s )
      when ErrorAction
        out << sprintf( "  %-12s  error\n", tok.to_s ) if @debug
      else
        bug! "act is not shift/reduce/accept: act=#{act}(#{act.type})"
      end
    end

    def outsrconf( out, confs )
      confs.each do |c|
        r = c.reduce
        out << sprintf( "  %-12s  [reduce using rule %d (%s)]\n",
                        c.shift.to_s, r.ruleid, r.symbol.to_s )
      end
    end

    def outrrconf( out, confs )
      confs.each do |c|
        r = c.low_prec
        out << sprintf( "  %-12s  [reduce using rule %d (%s)]\n",
                        c.token.to_s, r.ruleid, r.symbol.to_s )
      end
    end


    #####


    def output_rule( out )
      out << "-------- Grammar --------\n\n"
      @ruletable.each_rule do |rl|
        if @debug or rl.ident != 0 then
          out << sprintf( "rule %d %s: %s\n\n",
            rl.ident, rl.symbol.to_s, rl.tokens.join(' ') )
        end
      end

      return out
    end


    #####


    def output_token( out )
      out << "------- Token data -------\n\n"

      out << "**Nonterminals, with rules where they appear\n\n"
      tmp = "**Terminals, with rules where they appear\n\n"

      @tokentable.each do |tok|
        if tok.terminal? then
          terminal_out( tmp, tok )
        else
          nonterminal_out( out, tok )
        end
      end

      out << "\n" << tmp

      return out
    end

    def terminal_out( out, tok )
      tmp = <<SRC
  %s (%d) %s

SRC
      out << sprintf( tmp, tok.to_s, tok.tokenid, locatestr( tok.locate ) )
    end

    def nonterminal_out( out, tok )
      tmp = <<SRC
  %s (%d)
    on right: %s
    on left : %s
SRC
      out << sprintf( tmp, tok.to_s, tok.tokenid,
                      locatestr( tok.locate ), locatestr( tok.heads ) )
    end
    
    def locatestr( ptrs )
      arr = ptrs.collect {|ptr| i = ptr.rule.ident; i == 0 ? nil : i }
      arr.compact!
      arr.join(' ')
    end

  end

end   # module Racc
