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

  class Accept  ; end
  class Shift   ; end

  class Dammy   ; end
  class Default ; end
  Anchor = false


  private


  abstract :next_token
  abstract :next_value
  abstract :peep_token


  def do_parse
    lr_action_table = self.type::LR_action_table
    lr_goto_table   = self.type::LR_goto_table

    if self.type::DEBUG_PARSER and @__debug__ then
      tostbl = self.type::TOKEN_TO_S_TABLE
    else
      @__debug__ = false
      tostbl = nil
    end

    state    = [ 0 ]
    curstate = 0

    sstack = []
    vstack = []


    while true do
      #
      # dicide action
      #

      tact = lr_action_table[ curstate ]

      if tact.type == Hash then
        # look ahead
        act = tact[ peep_token ]
        unless act then act = tact[ Default ] end
      else
        act = tact
      end

      __showact__( tact, act, tostbl ) if @__debug__

      if act == Shift then
        #
        # shift
        #

        tok = next_token
        sstack.push tok
        vstack.push next_value

        __shift__( sstack, tok, tostbl ) if @__debug__

      elsif Integer === act then
        #
        # reduce
        #

        ret = send( act, vstack, sstack, state )
        vstack.push ret

        curstate = state[-1]
        if sstack[-1] == Accept then break end

        __reduce__( sstack, tostbl ) if @__debug__

      else
        #
        # error
        #

        if tact then
          if act then
            bug! "state #{curstate}, wrong act type #{act.type}"
          else
            __error_handler__( state, sstack, vstack, false )
          end
        else
          bug! "in state #{curstate}, tact is nil (tact=#{tact})"
        end
      end

      #
      # goto
      #

      unless hsh = lr_goto_table[ curstate ] then
        bug! "reduce state (ID #{curstate}) is current"
      end

      unless curstate = hsh[ sstack[-1] ] then
        __error_handler__( state, sstack, vstack, true )
      end

      state.push curstate

      __showstate__( state, curstate ) if @__debug__
    end
    
    __accept__ if @__debug__

    return vstack[0]
  end


  def on_error( etok, sstack, vstack, stat )
    raise ParseError,
      "\n\nparse error: unexpected token '#{etok}', in state #{stat[-1]}"
  end


  def __error_handler__( state, sstack, vstack, la )

    next_value if la   # discard one value ... fix!
    etok = next_value

    begin
      on_error( etok, sstack, vstack, state )
    rescue ParseError
      raise
    rescue
      raise( ParseError,
        "raised in user define 'on_error', message:\n#{$!}" )
    end
  end



  # for debugging output

  def __showact__( tact, act, tbl )
    if tact.type == Hash then
      puts 'lookaheading...'
      
      if act == Shift then
        print 'shift   '
      else
        print 'reduce '
      end

    elsif tact == Shift then
      print 'shift   '

    else
      print 'reduce '
    end
  end

  def __shift__( stack, tok, tbl )
    puts tbl[ tok ]
    __showstack__( stack, tbl )
  end

  def __accept__
    puts "accept\n\n"
  end

  def __reduce__( stack, tbl )
    __showstack__( stack, tbl )
  end

  def __showstack__( stack, tbl )
    print 'stack   ['
    stack.each{|sim| print ' ', tbl[ sim ] }
    print " ]\n\n"
  end

  def __showstate__( state, curstate )
    print "goto    #{curstate}\n"
    print 'stack   ['
    state.each{|st| print ' ', st }
    print " ]\n\n"
  end

end
