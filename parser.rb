#
# parser.rb
#
#    Copyright(c) 1999 Minero Aoki
#    aamine@dp.u-netsurf.ne.jp
#

require 'extmod'
require 'bug'


class ParseError < StandardError ; end


class Parser

  Shift   = Integer
  Reduce  = Array
  Accept  = Object.new

  Dammy   = Object.new
  Default = Object.new
  Anchor  = false


  private


  abstract :next_token


  def do_parse

    #
    # local parameters
    #

    lr_action_table = self.type::LR_action_table
    lr_goto_table   = self.type::LR_goto_table

    state    = [ 0 ]
    curstate = 0

    tstack = []
    vstack = []

    atmp = next_token
    tok = atmp[0]
    val = atmp[1]

    hash = nil
    act  = nil

    len       = nil
    reduce_to = nil

    tmp_t = nil
    tmp_v = nil

    void_array = []

    unless self.type::DEBUG_PARSER then
      @yydebug = false
    end


    #
    # LR parsing algorithm main loop
    #

    while true do

      hash = lr_action_table[ curstate ]
      act = (hash[ tok ] or hash[ Default ])

      case act
      when Shift

        tstack.push tok
        vstack.push val

        _shift( tok, tstack ) if @yydebug

        curstate = act
        state.push curstate

        atmp = next_token
        tok = atmp[0]
        val = atmp[1]

      when Reduce

        # act = [len, reduce_to, method_ID]

        len       = act[0]
        reduce_to = act[1]

        tmp_t = tstack[ -len, len ]
        tmp_v = vstack[ -len, len ]
        tstack[ -len, len ] = void_array
        vstack[ -len, len ] = void_array
        state[ -len, len ]  = void_array

        # tstack must be renewed AFTER method calling
        vstack.push send( act[2], tmp_t, tmp_v, tstack, vstack, state )
        tstack.push reduce_to

        break if reduce_to == Accept

        _reduce( tmp_t, reduce_to, tstack ) if @yydebug

        curstate = lr_goto_table[ state[-1] ][ reduce_to ]
        state.push curstate

      when Accept

        break   # not used yet

      else
        unless act then
          _error_handler( tok, val, tstack, vstack, state )
        else
          bug! "act is not Shift/Reduce, '#{act}'(#{act.type})"
        end
      end

      _print_state( curstate, state ) if @yydebug
    end

    _accept if @yydebug

    return vstack[0]
  end


  def _error_handler( tok, val, tstack, vstack, state )
    begin
      on_error( tok, val, tstack, vstack, state )
    rescue ParseError
      raise
    rescue
      raise ParseError, "raised in user define 'on_error', message:\n#{$!}"
    end
  end


  def on_error( tok, val, tstack, vstack, state )
    raise ParseError,
      "\nunexpected token '#{val}', in state #{state[-1]}"
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
