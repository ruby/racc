#
# parser.rb
#
#   Copyright (c) 1999 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#
#   This program is free software.
#   You can distribute/modify this program under the terms of
#   the GNU Lesser General Public License version 2 or later.
#

unless defined?(::ParseError) then
  class ParseError < StandardError ; end
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
  # Racc_Main_Parsing_Routine = :_rb_parse


  def next_token
    raise NotImplementError, "#{self.type}#next_token must be defined"
  end


  def do_parse
    unless self.type::DEBUG_PARSER then
      @yydebug = false
    end
    @yydebug = @yydebug ? true : false

    t = self.type
    send( Racc_Main_Parsing_Routine,
          t::LR_action_table,
          t::LR_action_table_ptr,
          t::LR_goto_table,
          t::LR_goto_table_ptr,
          t::LR_reduce_table,
          t::LR_token_table,
          t::LR_shift_n,
          t::LR_reduce_n,
          false )
  end


  def _rb_parse( action_table, action_ptr, goto_table, goto_ptr,
                 reduce_table, token_table, shift_n, reduce_n,
                 in_debug )
    #
    # local variables
    #

    state    = [ 0 ]
    curstate = 0

    tstack = []
    vstack = []

    atmp = tok = val = t = nil
    read_next = true

    act = i = ii = nil

    errstatus = 0
    nerr = 0

    t_def = -1   # default token
    t_end = 0    # $end
    t_err = 1    # error token

    #
    # LR parsing algorithm main loop
    #

    while true do

      if read_next then
        if t != t_end then
          atmp = next_token
          tok = atmp[0]
          val = atmp[1]
          t = (token_table[tok] or t_err)

          read_next = false
        end
      end

      i = action_ptr[curstate]
      while true do
        ii = action_table[i]
        if ii == t or ii == t_def then
          act = action_table[i+1]
          break
        end
        i += 2
      end

      if act > 0 and act < shift_n then
        #
        # shift
        #

        if errstatus > 0 then
          errstatus -= 1
        end

        tstack.push t if @yydebug
        vstack.push val

        _shift( t, tstack ) if @yydebug

        curstate = act
        state.push curstate

        read_next = true

      elsif act < 0 and act > -reduce_n then
        #
        # reduce
        #

        curstate = _do_reduce( action_table, action_ptr,
                               goto_table, goto_ptr, reduce_table,
                               state, curstate, vstack, tstack,
                               act )
        state.push curstate

      elsif act == shift_n then
        #
        # accept
        #

        _accept if @yydebug
        break

      elsif act == -reduce_n then
        #
        # error
        #

        case errstatus
        when 0
          nerr += 1
          on_error t, val, vstack
        when 3
          if t == t_end then
            return nil
          end
          read_next = true
        end
        errstatus = 3

        while true do
          i = action_ptr[curstate]
          while true do
            ii = action_table[i]
            if ii == t_def then
              break
            end
            if ii == t_err then
              act = action_table[i+1]
              break
            end
            i += 2
          end

          break if act != -reduce_n

          return nil if state.size < 2
          state.pop
          vstack.pop
          tstack.pop if @yydebug
          curstate = state[-1]
        end

        if act > 0 and act < shift_n then
          #
          # err-shift
          #
          tstack.push t_err if @yydebug
          vstack.push nil

          _shift( t_err, tstack ) if @yydebug

          curstate = act
          state.push curstate
          
        elsif act < 0 and act > -reduce_n then
          #
          # err-reduce
          #
          curstate = _do_reduce( action_table, action_ptr,
                                 goto_table, goto_ptr, reduce_table,
                                 state, curstate, vstack, tstack,
                                 act )
          state.push curstate

        elsif act == shift_n then
          #
          # err-accept
          #
          _accept if @yydebug
          break

        else
          raise RuntimeError, "[Racc Bug] wrong act value #{act.inspect}"
        end

      else
        raise RuntimeError, "[Racc Bug] unknown action #{act.inspect}"
      end

      _print_state( curstate, state ) if @yydebug
    end

    vstack[0]
  end


  def on_error( t, val, vstack )
    raise ParseError, "\nunexpected token #{val.inspect}"
  end


  def _do_reduce( action_table, action_ptr,
                  goto_table, goto_ptr, reduce_table,
                  state, curstate, vstack, tstack,
                  act )
    i = act * -3
    ii = nil
    len       = reduce_table[i]
    reduce_to = reduce_table[i+1]
    method_id = reduce_table[i+2]
    void_array = []

    tmp_t = tstack[ -len, len ] if @yydebug
    tmp_v = vstack[ -len, len ]
    tstack[ -len, len ] = void_array if @yydebug
    vstack[ -len, len ] = void_array
    state[ -len, len ]  = void_array

    # tstack must be renewed AFTER method calling
    vstack.push( (method_id == :_reduce_none) ?
                     tmp_v[0] : send(method_id, tmp_v, vstack, tmp_v[0]) )
    tstack.push reduce_to

    _reduce( tmp_t, reduce_to, tstack ) if @yydebug

    i = goto_ptr[state[-1]]
    while true do
      ii = goto_table[i]
      if ii == reduce_to or ii == 0 then
        curstate = goto_table[i+1]
        break
      end
      i += 2
    end

    curstate
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
    unless ret = self.type::TOKEN_TO_S_TABLE[tok] then
      raise RuntimeError, "[Racc Bug] can't convert token #{tok} to string"
    end
    ret
  end

end


end   # module Racc
