#
# raccs.rb
#
#   Copyright (c) 1999 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#
#   This library is free (and open source) software.
#   You can distribute/modify this library under the terms of
#   the GNU Library General Public License.
#

require 'racc/scanner'
require 'amstd/bug'


module Racc

  class RaccScanner < Scanner

    # pattern

    COMMENT  = /\A\#[^\n\r]*/
    BEGIN_C  = /\A\/\*[^\n\r\*\/]*/
    ATOM     = /\A[a-zA-Z_]\w*/
    USERCODE = /\A(?:\n|\r\n|\r)\-\-\-\-+/


    def initialize( str )
      super
      @rule_seen = false
      @eol_seen = false
      @token_seen = false
    end

    def scan
      ret = nil

      while true do
        unless @scan.rest? then
          ret = [false, '$']
          break
        end

        @scan.skip SPACE
        unless @scan.skip COMMENT then
          if @scan.skip BEGIN_C then
            scan_comment
            next
          end
        end

        if temp = @scan.scan( USERCODE ) then
          @lineno += 1
          @scan.clear
          next
        end

        if @scan.skip EOL then
          eol_found
          next
        end

        if atm = @scan.scan( ATOM ) then
          ret = scan_atom( atm )
          break
        end

        case fch = @scan.getch
        when '"', "'"
          ret = [:STRING, scan_string( fch )]
        when '{'
          no = lineno
          ret = [:ACTION, [ scan_action, no ]]
        else
          ret = [fch, fch]
        end

        break
      end

      debug_report ret if @debug
      ret
    end



    private


    STOS = {
      'end'      => :XEND,
      'token'    => :XTOKEN,
      'right'    => :XRIGHT,
      'left'     => :XLEFT,
      'nonassoc' => :XNONASSOC,
      'preclow'  => :XPRECLOW,
      'prechigh' => :XPRECHIGH,
      'start'    => :XSTART,
      'class'    => :XCLASS,
      'rule'     => :XRULE
    }

    def scan_atom( cur )
# puts "eol=#{@eol_seen}"
# puts "tok=#{@token_seen}"
      if cur == 'end' then
        sret = :XEND
        @token_seen = false
      else
        if @eol_seen and not @token_seen then
          sret = STOS[ cur ] || :TOKEN
        else
          sret = :TOKEN
        end

        case sret
        when :XRULE  then @rule_seen  = true
        when :XTOKEN then @token_seen = true
        end
      end
      @eol_seen = false

# printf "%10s : %10s\n", cur, sret.id2name
      [sret, cur.intern]
    end


    def eol_found
# puts
      @lineno += 1
      @eol_seen = true unless @rule_seen
    end

  # BEGIN_C   = /\A\/\*[^\n\r\*\/]*/o
    COM_ENT   = /\A[^\n\r*]+/o
    COM_ENT2  = /\A\*+[^*\/\r\n]/o
    END_C     = /\A\*+\//o

    def scan_comment
      while @scan.rest? do
        if    @scan.skip COM_ENT
        elsif @scan.skip COM_ENT2
        elsif @scan.skip EOL      then eol_found
        elsif @scan.skip END_C    then return
        else
          scan_bug! 'in comment, no exp match'
        end
      end
      scan_error! 'find unterminated comment'
    end


    SKIP         = /\A[^\'\"\`\{\}\/\#\r\n]+/o
    COMMENT_CONT = /\A[^\r\n]*/o

    def scan_action
      ret  = ''
      nest = 0
      while @scan.rest? do
        if temp = @scan.scan( SKIP ) then
          ret << temp
        end
        if temp = @scan.scan( EOL ) then
          ret << temp
          @lineno += 1
          next
        end

        case ch = @scan.getch
        when '{'
          nest += 1
          ret << ch

        when '}'
          nest -= 1
          if nest < 0 then
            break
          end
          ret << ch

        when "'", '"', '`'
          ret << ch << scan_string( ch ) << ch

        when '/'
          if SPACE === ret[-1,1] then
            if @scan.peep(1) != '=' then
              ret << ch << scan_string( ch ) << ch
              next
            end
          end
          ret << ch

        when '#'
          ret << ch << @scan.scan( COMMENT_CONT ) << @scan.scan( EOL )
          @lineno += 1

        else
          bug!
        end
      end

      return ret
    end

  end

end
