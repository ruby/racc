#
# $Id$
#
# Copyright (c) 1999-2005 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".
#

require 'racc/compat'

module Racc

  class Formatter
    def initialize(racc)
      @ruletable   = racc.ruletable
      @symboltable = racc.symboltable
      @statetable  = racc.statetable
      @actions     = racc.statetable.actions

      @fname       = racc.filename
      @debug       = racc.debug         ? true : false
      @dsrc        = racc.debug_parser  ? true : false
      @line        = racc.convert_line  ? true : false
      @omit        = racc.omit_action   ? true : false
      @result      = racc.result_var    ? true : false
      @showall     = racc.d_la || racc.d_state
    end
  end


  class CodeGenerator < Formatter

    def output(out)
      out.print "\n##### racc #{Racc::Version} generates ###\n\n"
      output_reduce_table out
      output_action_table out
      output_goto_table out
      output_token_table out
      output_other out
      out.puts '##### racc system variables end #####'
      output_actions out
    end

    private

    def output_reduce_table(out)
      out << "racc_reduce_table = [\n"
      out << " 0, 0, :racc_error,"
      sep = "\n"
      sep_rest = ",\n"
      @ruletable.each_with_index do |rl, i|
        next if i == 0
        out.print sep; sep = sep_rest
        out.printf ' %d, %d, :_reduce_%s',
                   rl.size,
                   rl.target.ident,
                   (@omit and not rl.action) ? 'none' : i.to_s
      end
      out << " ]\n\n"
      out << "racc_reduce_n = #{@actions.reduce_n}\n\n"
      out << "racc_shift_n = #{@actions.shift_n}\n\n"
    end

    def output_action_table(out)
      tbl  = []   # yytable
      chk  = []   # yycheck
      defa = []   # yydefact
      ptr  = []   # yypact
      state = tmp = min = max = i = nil
      e1 = []
      e2 = []

      @statetable.each do |state|
        defa.push act2actid(state.defact)

        if state.action.empty?
          ptr.push nil
          next
        end
        tmp = []
        state.action.each do |tok, act|
          tmp[tok.ident] = act2actid(act)
        end
        addent e1, e2, tmp, state.ident, ptr
      end
      set_table e1, e2, tbl, chk, ptr

      output_table out, tbl, 'racc_action_table'
      output_table out, chk, 'racc_action_check'
      output_table out, ptr, 'racc_action_pointer'
      output_table out, defa, 'racc_action_default'
    end

    def output_goto_table(out)
      tbl  = []   # yytable (2)
      chk  = []   # yycheck (2)
      ptr  = []   # yypgoto
      defg = []   # yydefgoto
      state = dflt = tmp = freq = min = max = i = nil
      e1 = []
      e2 = []

      @symboltable.each_nonterm do |tok|
        tmp = []

        #
        # decide default
        #
        freq = Array.new(@statetable.size, 0)
        @statetable.each do |state|
          st = state.goto_table[tok]
          if st
            st = st.ident
            freq[st] += 1
          end
          tmp[state.ident] = st
        end
        max = freq.max
        if max > 1
          dflt = freq.index( max )
          tmp.map! {|i| dflt == i ? nil : i }
        else
          dflt = nil
        end

        # default
        defg.push dflt

        #
        # delete default value
        #
        tmp.pop until tmp[-1] or tmp.empty?
        if tmp.compact.empty?
          # only default
          ptr.push nil
          next
        end

        addent e1, e2, tmp, (tok.ident - @symboltable.nt_base), ptr
      end
      set_table e1, e2, tbl, chk, ptr

      output_table out, tbl, 'racc_goto_table'
      output_table out, chk, 'racc_goto_check'
      output_table out, ptr, 'racc_goto_pointer'
      output_table out, defg, 'racc_goto_default'
    end

    def addent(all, dummy, arr, chkval, ptr)
      max = arr.size
      min = nil
      item = idx = nil
      arr.each_with_index do |item,idx|
        if item
          min ||= idx
        end
      end
      ptr.push(-7777)    # mark

      arr = arr[min...max]
      ent = [ arr, chkval, mkmapexp(arr), min, ptr.size - 1 ]
      all.push ent
    end

    unless defined? RegexpError
      RegexpError = RegxpError
    end
    begin
      tmp = 2 ** 16
      begin
        Regexp.new("a{#{tmp}}")
        RE_DUP_MAX = tmp
      rescue RegexpError
        tmp /= 2
        retry
      end
      raise ArgumentError, 'dummy error to clear ruby_errinfo'
    rescue ArgumentError
      ;
    end

    def mkmapexp(arr)
      i = ii = 0
      as = arr.size
      map = ''
      maxdup = RE_DUP_MAX
      curr = nil

      while i < as
        ii = i + 1
        if arr[i]
          ii += 1 while ii < as and arr[ii]
          curr = '-'
        else
          ii += 1 while ii < as and not arr[ii]
          curr = '.'
        end

        offset = ii - i
        if offset == 1
          map << curr
        else
          while offset > maxdup
            map << "#{curr}{#{maxdup}}"
            offset -= maxdup
          end
          map << "#{curr}{#{offset}}" if offset > 1
        end
        i = ii
      end

      Regexp.compile(map, 'n')
    end

    def set_table(entries, dummy, tbl, chk, ptr)
      upper = 0
      map = '-' * 10240

      # sort long to short
      entries.sort! {|a,b| b[0].size <=> a[0].size }

      entries.each do |arr, chkval, expr, min, ptri|
        if upper + arr.size > map.size
          map << '-' * (arr.size + 1024)
        end
        idx = map.index(expr)
        ptr[ptri] = idx - min
        arr.each_with_index do |item, i|
          if item
            i += idx
            tbl[i] = item
            chk[i] = chkval
            map[i] = ?o
          end
        end
        upper = idx + arr.size
      end
    end

    def act2actid(act)
      case act
      when Shift  then act.goto_id
      when Reduce then -act.ruleid
      when Accept then @actions.shift_n
      when Error  then @actions.reduce_n * -1
      else
        raise "racc: fatal: wrong act type #{act.class} in action table"
      end
    end

    def output_table(out, tab, label)
      if tab.size > 2000
        #
        # compressed table
        #
        output_table_c out, tab, label
      else
        #
        # normal array
        #
        output_table_s out, tab, label
      end
    end

    def output_table_c(out, tab, label)
      sep  = "\n"
      nsep = ",\n"
      buf  = ''
      com  = ''
      ncom = ','
      co   = com

      out.print 'clist = ['
      tab.each do |i|
        buf << co << i.to_s; co = ncom
        if buf.size > 66
          out.print sep; sep = nsep
          out.print "'", buf, "'"
          buf = ''
          co = com
        end
      end
      unless buf.empty?
        out.print sep
        out.print "'", buf, "'"
      end
      out.puts ' ]'

      out.print(<<EOS)
#{label} = arr = Array.new(#{tab.size}, nil)
str = a = i = nil
idx = 0
clist.each do |str|
  str.split(',', -1).each do |i|
    arr[idx] = i.to_i unless i.empty?
    idx += 1
  end
end

EOS
    end

    def output_table_s(out, tab, label)
      sep  = ''
      nsep = ','
      buf  = ''
      i = 0

      out.puts "#{label} = ["
      tab.each do |t|
        buf << sep ; sep = nsep
        if i == 10
          i = 0
          buf << "\n"
          out << buf
          buf = ''
        end
        buf << (t ? sprintf('%6d', t) : '   nil')
        i += 1
      end
      out << buf unless buf.empty?
      out.print " ]\n\n"
    end

    def output_token_table(out)
      sep = "\n"
      sep_rest = ",\n"
      out << "racc_token_table = {"
      @symboltable.each do |tok|
        if tok.terminal?
          out.print sep; sep = sep_rest
          out.printf " %s => %d", tok.uneval, tok.ident
        end
      end
      out << " }\n\n"
    end

    def output_other(out)
      out << "racc_use_result_var = #{@result}\n\n"
      out.print(<<EOS)
racc_nt_base = #{@symboltable.nt_base}

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
 racc_reduce_n,
 racc_use_result_var ]

EOS
      out << "Racc_token_to_s_table = [\n"
      out << @symboltable.map {|tok|
              "'" + tok.to_s.gsub(/'/, '\\\'') + "'" }.join(",\n")
      out << "]\n\n"
      out << "Racc_debug_parser = #{@dsrc}\n\n"
    end

    def output_actions(out)
      rl = act = nil

      if @result
        result1 = ', result '
        result2 = "\n   result"
        defact = ''
      else
        result1 = result2 = ''
        defact = '  val[0]'
      end
      result = @result ? ', result ' : ''
      if @line
        src = <<'--'

module_eval <<'.,.,', '%s', %d
  def _reduce_%d( val, _values%s)
%s%s
  end
%s
--
      else
        src = <<'--'

  def _reduce_%d( val, _values%s)
%s%s
  end
--
      end

      @ruletable.each_rule do |rl|
        act = rl.action
        if not act and @omit
          out.printf "\n # reduce %d omitted\n",
                     rl.ident
        else
          act ||= defact
          act.sub!(/\s+\z/, '')
          if @line
            i = rl.lineno
            while m = /\A[ \t\f]*(?:\n|\r\n|\r)/.match(act)
              act = m.post_match
              i += 1
            end
            delim = '.,.,'
            while act.index(delim)
              delim *= 2
            end
            out.printf src, @fname, i - 1, rl.ident,
                       result1, act, result2, delim
          else
            act.sub!(/\A\s*(?:\n|\r\n|\r)/, '')
            out.printf src, rl.ident,
                       result1, act, result2
          end
        end
      end
      out.printf <<'--', result, (@result ? 'result' : 'val[0]')

 def _reduce_none( val, _values%s)
  %s
 end
--
      out.puts
    end

  end   # class CodeGenerator


  class VerboseOutputter < Formatter

    def output(out)
      output_conflict out; out.puts
      output_useless  out; out.puts
      output_rule     out; out.puts
      output_token    out; out.puts
      output_state    out
    end

    #
    # Warnings
    #

    def output_conflict(out)
      @statetable.each do |state|
        if state.srconf
          out.printf "state %d contains %d shift/reduce conflicts\n",
                     state.stateid, state.srconf.size
        end
        if state.rrconf
          out.printf "state %d contains %d reduce/reduce conflicts\n",
                     state.stateid, state.rrconf.size
        end
      end
    end

    def output_useless(out)
      rl = t = nil
      used = []
      @ruletable.each do |rl|
        if rl.useless?
          out.printf "rule %d (%s) never reduced\n",
                     rl.ident, rl.target.to_s
        end
      end
      @symboltable.each_nonterm do |t|
        if t.useless?
          out.printf "useless nonterminal %s\n", t.to_s
        end
      end
    end

    #
    # States
    #

    def output_state(out)
      ptr = nil
      out << "--------- State ---------\n"

      @statetable.each do |state|
        out << "\nstate #{state.ident}\n\n"

        (@showall ? state.closure : state.core).each do |ptr|
          pointer_out(out, ptr) if ptr.rule.ident != 0 or @showall
        end
        out << "\n"

        action_out out, state
      end
    end

    def pointer_out(out, ptr)
      buf = sprintf("%4d) %s :", ptr.rule.ident, ptr.rule.target.to_s)
      ptr.rule.symbols.each_with_index do |tok, idx|
        buf << ' _' if idx == ptr.index
        buf << ' ' << tok.to_s
      end
      buf << ' _' if ptr.reduce?
      out.puts buf
    end

    def action_out(f, state)
      r = ''
      e = ''
      sr = state.srconf && state.srconf.dup
      rr = state.rrconf && state.rrconf.dup
      acts = state.action
      keys = acts.keys
      keys.sort! {|a,b| a.ident <=> b.ident }

      [ Shift, Reduce, Error, Accept ].each do |klass|
        keys.delete_if do |tok|
          act = acts[tok]
          if act.kind_of?(klass)
            outact f, tok, act
            if sr and c = sr.delete(tok)
              outsrconf f, c
            end
            if rr and c = rr.delete(tok)
              outrrconf f, c
            end

            true
          else
            false
          end
        end
      end
      sr.each {|tok, c| outsrconf f, c } if sr
      rr.each {|tok, c| outrrconf f, c } if rr

      act = state.defact
      if not act.kind_of?(Error) or @debug
        outact f, '$default', act
      end

      f.puts
      state.goto_table.each do |t, st|
        if t.nonterminal?
          f.printf "  %-12s  go to state %d\n", t.to_s, st.ident
        end
      end
    end

    def outact(f, t, act)
      case act
      when Shift
        f.printf "  %-12s  shift, and go to state %d\n", 
                 t.to_s, act.goto_id
      when Reduce
        f.printf "  %-12s  reduce using rule %d (%s)\n",
                 t.to_s, act.ruleid, act.rule.target.to_s
      when Accept
        f.printf "  %-12s  accept\n", t.to_s
      when Error
        f.printf "  %-12s  error\n", t.to_s
      else
        raise "racc: fatal: wrong act for outact: act=#{act}(#{act.class})"
      end
    end

    def outsrconf(f, confs)
      confs.each do |c|
        r = c.reduce
        f.printf "  %-12s  [reduce using rule %d (%s)]\n",
                 c.shift.to_s, r.ident, r.target.to_s
      end
    end

    def outrrconf(f, confs)
      confs.each do |c|
        r = c.low_prec
        f.printf "  %-12s  [reduce using rule %d (%s)]\n",
                 c.token.to_s, r.ident, r.target.to_s
      end
    end

    #
    # Rules
    #

    def output_rule(out)
      out.print "-------- Grammar --------\n\n"
      @ruletable.each_rule do |rl|
        if @debug or rl.ident != 0
          out.printf "rule %d %s: %s\n",
                     rl.ident, rl.target.to_s, rl.symbols.join(' ')
        end
      end
    end

    #
    # Tokens
    #

    def output_token(out)
      out.print "------- Symbols -------\n\n"

      out.print "**Nonterminals, with rules where they appear\n\n"
      @symboltable.each_nonterm do |t|
        tmp = <<SRC
  %s (%d)
    on right: %s
    on left : %s
SRC
        out.printf tmp, t.to_s, t.ident,
                   locatestr(t.locate), locatestr(t.heads)
      end

      out.print "\n**Terminals, with rules where they appear\n\n"
      @symboltable.each_terminal do |t|
        out.printf "  %s (%d) %s\n",
                   t.to_s, t.ident, locatestr(t.locate)
      end
    end

    def locatestr(ptrs)
      list = ptrs.map {|ptr|
                    i = ptr.rule.ident
                    (i == 0) ? nil : i
                  }
      list.compact!
      list.uniq!
      list.join(' ')
    end

  end   # class VerboseOutputter

end
