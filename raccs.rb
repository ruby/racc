#
# raccs.rb
#
#   Copyright (c) 1999,2000 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#
#   This program is free software.
#   You can distribute/modify this program under the terms of
#   the GNU Lesser General Public License version 2 or later.
#

require 'amstd/bug'


module Racc

  class ScanError < StandardError; end

  
  class RaccScanner

    def initialize( str )
      @lines  = str.split( /\n|\r\n|\r/ )
      @lineno = -1

      @line_head   = true
      @in_rule_blk = false
      @in_conv_blk = false

      @in_block = nil

      @debug = false

      next_line
    end

    def lineno
      @lineno + 1
    end

    attr :debug, true


    def scan
      ret = do_scan
      if @debug then
        $stderr.printf "%7d %-10s %s\n",
                       lineno, ret[0].inspect, ret[1].inspect
      end
      ret
    end

    def do_scan
      begin
        until @line.empty? do
          @line.sub! /\A\s+/, ''

          if /\A\#/ === @line then
            next_line

          elsif /\A\/\*/ === @line then
            skip_comment

          elsif m = /\A[a-zA-Z_]\w*/.match( @line ) then
            @line = m.post_match
            return check_atom( m[0] )

          elsif m = /\A./.match( @line ) then
            ch = m[0]
            @line = m.post_match
            case ch
            when '"', "'"
              return [:STRING, eval(scan_string ch)]
            when '{'
              no = lineno
              return [:ACTION, [scan_action, no]]
            else
              return [ch, ch]
            end

          else
            ;
          end
        end
      end while next_line

      [false, '$']
    end


    private

    def next_line
      @lineno += 1
      @line = @lines[ @lineno ]

      if not @line or /\A----/ === @line then
        @lines.clear
        @line = nil
        if @in_block then
          scan_error! sprintf('unterminated %s', @in_block)
        end

        false
      else
        @line.sub! /(?:\n|\r\n|\r)\z/, ''
        @line_head = true
        true
      end
    end


    ResWord = {
      'right'    => :XRIGHT,
      'left'     => :XLEFT,
      'nonassoc' => :XNONASSOC,
      'preclow'  => :XPRECLOW,
      'prechigh' => :XPRECHIGH,
      'token'    => :XTOKEN,
      'convert'  => :XCONV,
      'options'  => :XOPTION,
      'start'    => :XSTART,
      'class'    => :XCLASS,
      'rule'     => :XRULE,
      'end'      => :XEND
    }

    def check_atom( cur )
      if cur == 'end' then
        sret = :XEND
        @in_conv_blk = false
      else
        if @line_head and not @in_conv_blk then
          sret = ResWord[cur] || :XSYMBOL
        else
          sret = :XSYMBOL
        end

        case sret
        when :XRULE then @in_rule_blk = true
        when :XCONV then @in_conv_blk = true
        end
      end
      @line_head = false

      [sret, cur.intern]
    end


    def skip_comment
      @in_block = 'comment'
      until m = /\*\//.match( @line ) do
        next_line
      end
      @line = m.post_match
      @in_block = nil
    end


    def scan_action
      ret = ''
      nest = 1

      @in_block = 'action'

      begin
        pre = nil

        until @line.empty? do
          if m = /\A[^'"`{}%#\/]+/.match( @line ) then
            pre = m[0]
            ret << pre
            @line = m.post_match
            next
          end

          ch = @line[0,1]
          @line = @line[ 1, @line.size - 1 ]
          case ch
          when '{'
            nest += 1
            pre = ch
            ret << ch

          when '}'
            nest -= 1
            if nest == 0 then
              @in_block = nil
              return ret
            end
            pre = ch
            ret << ch

          when '#'
            ret << ch << @line
            break

          when "'", '"', '`'
            pre = scan_string( ch )
            ret << pre

          when '%'
            if (not pre or /\W/ === pre[-1,1]) and
               (tmp = @line[0,1]) and /[a-zA-Z=]/ === tmp then
              # % string
              ret << ch
              @line = @line[ 1, @line - 1 ]
              pre = scan_string( @line[1,1] )
            else
              # mod
              pre = ch
            end
            ret << pre

          when '/'
            if (not pre or /\W/ === pre[-1,1]) and
               (tmp = @line[0,1]) and not /[\s\=]/ === tmp or
               not tmp then
              # regexp
              pre = scan_string(ch)
            else
              # division
              pre = ch
            end
            ret << pre

          else
            bug!
          end
        end

        ret << "\n"
      end while next_line

      bug!
    end


    LEFT_TO_RIGHT = {
      '(' => ')',
      '{' => '}',
      '[' => ']',
      '<' => '>'
    }

    def scan_string( left )
      ret = left.dup
      term = LEFT_TO_RIGHT[left] || left
      eline = /\A(?:[^\\#{term}]+|\\.)*#{term}/

      @in_block = 'string'
      begin
        if m = eline.match( @line ) then
          ret << m[0]
          @line = m.post_match
          break
        else
          ret << @line
        end
      end while next_line
      @in_block = nil

      ret
    end


    def scan_error!( msg )
      raise ScanError, "#{lineno}: #{msg}"
    end
          
  end

end   # module Racc
