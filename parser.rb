#
# parser.rb
#
#    Copyright(c) 1999 Minero Aoki
#    aamine@dp.u-netsurf.ne.jp
#

require 'amstd/extmod'
require 'amstd/bug'


class ParseError < StandardError ; end


class Parser

  private


  begin
    require 'racc/cparse'   # def _c_parse
    $Racc_Main_Parsing_Routine = :c
  rescue LoadError
    $Racc_Main_Parsing_Routine = :rb
  end


  abstract :next_token


  def do_parse
    unless self.type::DEBUG_PARSER then
      @yydebug = false
    end
    @yydebug = @yydebug ? true : false

    case $Racc_Main_Parsing_Routine
    when :c  then _c_parse false
    when :rb then _rb_parse
    else
      bug!
    end
  end


  def _rb_parse
    #
    # local parameters
    #

    action_table = self.type::LR_action_table
    action_ptr   = self.type::LR_action_table_ptr
    goto_table   = self.type::LR_goto_table
    goto_ptr     = self.type::LR_goto_table_ptr
    reduce_table = self.type::LR_reduce_table
    token_table  = self.type::LR_token_table
    shift_n      = self.type::LR_shift_n
    reduce_n     = self.type::LR_reduce_n

    state    = [ 0 ]
    curstate = 0

    tstack = []
    vstack = []

    atmp = tok = val = t = nil
    read_next = true

    act = nil
    i = ii  = nil

    len       = nil
    reduce_to = nil
    method_id = nil

    tmp_t = nil
    tmp_v = nil

    void_array = []

    #
    # LR parsing algorithm main loop
    #

    while true do

      if read_next then
        if tok != false then
          atmp = next_token
          tok = atmp[0]
          val = atmp[1]
          t = token_table[tok]

          read_next = false
        end
      end

      i = action_ptr[curstate]
      while true do
        ii = action_table[i]
        if ii == t or ii == -1 then
          act = action_table[i+1]
          break
        end
        i += 2
      end

      if act > 0 and act < shift_n then
        #
        # shift
        #

        tstack.push t
        vstack.push val

        _shift( t, tstack ) if @yydebug

        curstate = act
        state.push curstate

        read_next = true

      elsif act < 0 and act > -reduce_n then
        #
        # reduce
        #

        i = act * -3
        len       = reduce_table[i]
        reduce_to = reduce_table[i+1]
        method_id = reduce_table[i+2]

        tmp_t = tstack[ -len, len ] if @yydebug
        tmp_v = vstack[ -len, len ]
        tstack[ -len, len ] = void_array if @yydebug
        vstack[ -len, len ] = void_array
        state[ -len, len ]  = void_array

        # tstack must be renewed AFTER method calling
        vstack.push send( method_id, tmp_v, vstack, tmp_v[0] )
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

        on_error( t, val, vstack )

      else
        bug! "unknown action #{act}"
      end

      _print_state( curstate, state ) if @yydebug
    end

    vstack[0]
  end


  def on_error( t, val, vstack )
    raise ParseError, "unexpected token '#{val.inspect}'"
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
      bug! "can't convert token #{tok} to string"
    end
    ret
  end

end
