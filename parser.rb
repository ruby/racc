#
# parser.rb
#
#   Copyright (c) 1999 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#
#   This program is free software.
#   You can distribute/modify this program under the terms of
#   the GNU Lesser General Public License version 2 or later.
#

unless defined? ParseError then
  class ParseError < StandardError; end
end


module Racc


class Parser

  private


  begin
    require 'racc/cparse'   # def _c_parse
    Racc_Main_Parsing_Routine = :_c_parse
  rescue LoadError
    Racc_Main_Parsing_Routine = :_rb_parse
  end


  def next_token
    raise NotImplementError, "#{self.type}#next_token must be defined"
  end


  def do_parse
    t = self.type
    unless t::Racc_debug_parser then
      @yydebug = false
    end
    @yydebug = @yydebug ? true : false

    send Racc_Main_Parsing_Routine, t::Racc_arg, false
  end


  def _rb_parse( arg, in_debug )
    action_table, action_check, action_default, action_pointer,
    goto_table, goto_check, goto_default, goto_pointer,
    nt_base, reduce_table, token_table, shift_n, reduce_n = *arg

    #
    # local variables
    #

    state    = [ 0 ]
    curstate = 0

    tstack = []
    vstack = []

    atmp = tok = val = t = nil
    act = tmp = code = i = nil
    read_next = true

    @racc_error_status = 0
    nerr = 0
    user_yyerror = false

    t_end = 0    # $end
    t_err = 1    # error token

    yydebug = @yydebug

    #
    # LR parsing algorithm main loop
    #

    while true do

      if i = action_pointer[ curstate ] then
        if read_next then
          if t != t_end then
            atmp = next_token
            tok = atmp[0]
            val = atmp[1]
            t = (token_table[tok] or t_err)

            read_next = false
          end
        end
        i += t
        if i >= 0 and act = action_table[i] and
           action_check[i] == curstate then
        else
          act = action_default[ curstate ]
        end
      else
        act = action_default[ curstate ]
      end

  while true do
      if act > 0 and act < shift_n then
        #
        # shift
        #

        if @racc_error_status > 0 then
          @racc_error_status -= 1
        end

        tstack.push t if yydebug
        vstack.push val

        _shift( t, tstack ) if yydebug

        curstate = act
        state.push curstate

        read_next = true

      elsif act < 0 and act > -reduce_n then
        #
        # reduce
        #

        code = catch( :racc_jump ) {
          curstate = _do_reduce( arg, state, vstack, tstack, act )
          state.push curstate; 0
        }
        unless code == 0 then
          case code
          when 1 # yyerror
            act = -reduce_n
            user_yyerror = true
            next
          when 2 # yyaccept
            act = shift_n
            next
          else
            raise RuntimeError, '[Racc Bug] unknown jump code'
          end
        end

      elsif act == shift_n then
        #
        # accept
        #

        _accept if yydebug
        return vstack[0]

      elsif act == -reduce_n then
        #
        # error
        #

        case @racc_error_status
        when 0
          unless user_yyerror then
            nerr += 1
            on_error( t, val, vstack )
          end
        when 3
          if t == t_end then
            return nil
          end
          read_next = true
        end
        user_yyerror = false
        @racc_error_status = 3

        while true do
          if i = action_pointer[curstate] then
            i += t_err
            if i >= 0 and
               (act = action_table[i]) and
               action_check[i] == curstate then
              break
            end
          end

          return nil if state.size < 2
          state.pop
          vstack.pop
          tstack.pop if yydebug
          curstate = state[-1]
        end

        if act > 0 and act < shift_n then
          #
          # err-shift
          #
          tstack.push t_err if yydebug
          vstack.push val

          _shift( t_err, tstack ) if yydebug

          curstate = act
          state.push curstate
          
        elsif act < 0 and act > -reduce_n then
          #
          # err-reduce
          #
          code = catch( :racc_jump ) {
            curstate = _do_reduce( arg, state, vstack, tstack, act )
            state.push curstate; 0
          }
          unless code == 0 then
            case code
            when 1 # yyerror
              act = -reduce_n
              user_yyerror = true
              next
            when 2 # yyaccept
              act = shift_n
              next
            else
              raise RuntimeError, '[Racc Bug] unknown jump code'
            end
          end

        elsif act == shift_n then
          #
          # err-accept
          #
          _accept if yydebug
          return vstack[0]

        else
          raise RuntimeError, "[Racc Bug] wrong act value #{act.inspect}"
        end

      else
        raise RuntimeError, "[Racc Bug] unknown action #{act.inspect}"
      end
  break; end

      _print_state( curstate, state ) if yydebug
    end

    raise RuntimeError, '[Racc Bug] must not reach here'
  end


  def on_error( t, val, vstack )
    raise ParseError, "\nunexpected token #{val.inspect}"
  end


  def _do_reduce( arg, state, vstack, tstack, act )
    action_table, action_check, action_default, action_pointer,
    goto_table, goto_check, goto_default, goto_pointer,
    nt_base, reduce_table, token_table, shift_n, reduce_n = *arg

    i = act * -3
    len       = reduce_table[i]
    reduce_to = reduce_table[i+1]
    method_id = reduce_table[i+2]
    void_array = []

    tmp_t = tstack[ -len, len ] if @yydebug
    tmp_v = vstack[ -len, len ]
    tstack[ -len, len ] = void_array if @yydebug
    vstack[ -len, len ] = void_array
    state[ -len, len ]  = void_array

    # tstack must be renewed AFTER method call
    vstack.push( (method_id == :_reduce_none) ?
                     tmp_v[0] : send(method_id, tmp_v, vstack, tmp_v[0]) )
    tstack.push reduce_to

    _reduce( tmp_t, reduce_to, tstack ) if @yydebug

    k1 = reduce_to - nt_base
    if i = goto_pointer[ k1 ] then
      i += state[-1]
      if i >= 0 and (curstate = goto_table[i]) and goto_check[i] == k1 then
        return curstate
      end
    end
    goto_default[ k1 ]
  end

  def yyerror
    throw :racc_jump, 1
  end

  def yyaccept
    throw :racc_jump, 2
  end

  def yyerrok
    @racc_error_status = 0
  end


  # for debugging output

  def _shift( tok, tstack )
    print 'shift   ', _token2str(tok), "\n"
    _print_tokens( tstack, true )
    print "\n\n"
  end

  def _accept
    print "accept\n\n"
  end

  def _reduce( toks, sim, tstack )
    print 'reduce '
    if toks.size == 0 then
      print ' <none>'
    else
      _print_tokens( toks, false )
    end
    print ' --> '; puts _token2str(sim)
        
    _print_tokens( tstack, true )
    print "\n\n"
  end

  def _print_tokens( toks, bla )
    print '        [' if bla
    toks.each {|t| print ' ', _token2str(t) }
    print ' ]' if bla
  end

  def _print_state( curstate, state )
    puts  "goto    #{curstate}"
    print '        ['
    state.each {|st| print ' ', st }
    print " ]\n\n"
  end

  def _token2str( tok )
    unless ret = self.type::Racc_token_to_s_table[tok] then
      raise RuntimeError, "[Racc Bug] can't convert token #{tok} to string"
    end
    ret
  end

end


end   # module Racc
