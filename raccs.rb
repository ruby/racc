#
# raccs.rb
#
#   Copyright (c) 1999-2001 Minero Aoki <aamine@loveruby.net>
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
          @line.sub!( /\A\s+/, '' )

          if /\A\#/ === @line then
            break

          elsif /\A\/\*/ === @line then
            skip_comment

          elsif s = reads( /\A[a-zA-Z_]\w*/ ) then
            return check_atom(s)

          elsif s = reads( /\A\d+/ ) then
            return :DIGIT, s.to_i

          elsif ch = reads( /\A./ ) then
            case ch
            when '"', "'"
              return :STRING, eval(scan_quoted(ch))
            when '{'
              no = lineno
              return :ACTION, [scan_action, no]
            else
              if ch == '|' then
                @line_head = false
              end
              return ch, ch
            end

          else
            ;
          end
        end
      end while next_line

      return false, '$'
    end


    private

    def next_line
      @lineno += 1
      @line = @lines[ @lineno ]

      if not @line or /\A----/ === @line then
        @lines.clear
        @line = nil
        if @in_block then
          @lineno -= 1
          scan_error! sprintf('unterminated %s', @in_block)
        end

        false
      else
        @line.sub!( /(?:\n|\r\n|\r)\z/, '' )
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
      'expect'   => :XEXPECT,
      'class'    => :XCLASS,
      'rule'     => :XRULE,
      'end'      => :XEND
    }

    def check_atom( cur )
      if cur == 'end' then
        sret = :XEND
        @in_conv_blk = false
        @in_rule_blk = false
      else
        if @line_head and not @in_conv_blk and not @in_rule_blk then
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
      pre = nil

      @in_block = 'action'

      begin
        pre = nil
        if s = reads( /\A\s+/ ) then
          # does not set 'pre'
          ret << s
        end

        until @line.empty? do
          if s = reads( /\A[^'"`{}%#\/\$]+/ ) then
            ret << (pre = s)
            next
          end

          case ch = read(1)
          when '{'
            nest += 1
            ret << (pre = ch)

          when '}'
            nest -= 1
            if nest == 0 then
              @in_block = nil
              return ret
            end
            ret << (pre = ch)

          when '#'   # comment
            ret << ch << @line
            break

          when "'", '"', '`'
            ret << (pre = scan_quoted(ch))

          when '%'
            if literal_head? pre, @line then
              # % string, regexp, array
              ret << ch
              case ch = read(1)
              when /[qQx]/n
                ret << ch << (pre = scan_quoted(read(1), '%string'))
              when /w/n
                ret << ch << (pre = scan_quoted(read(1), '%array'))
              when /r/n
                ret << ch << (pre = scan_quoted(read(1), '%regexp'))
              when /[a-zA-Z0-9= ]/n   # does not include "_"
                scan_error! "unknown type of % literal '%#{ch}'"
              else
                ret << (pre = scan_quoted(ch, '%string'))
              end
            else
              # operator
              ret << '||op->' if $raccs_print_type
              ret << (pre = ch)
            end

          when '/'
            if literal_head? pre then
              # regexp
              ret << (pre = scan_quoted(ch, 'regexp'))
            else
              # operator
              ret << '||op->' if $raccs_print_type
              ret << (pre = ch)
            end

          when '$'   # gvar
            ret << ch << (pre = read(1))

          else
            bug!
          end
        end

        ret << "\n"
      end while next_line

      bug!
    end

    def literal_head?( pre, post )
      (not pre or not /[a-zA-Z_0-9]/n === pre[-1,1]) and
      not post.empty? and not /\A[\s\=]/n === post
    end


    def read( len )
      s = @line[0, len]
      @line = @line[len .. -1]
      s
    end

    def reads( re )
      if m = re.match( @line ) then
        @line = m.post_match
        m[0]
      else
        nil
      end
    end


    def scan_quoted( left, tag = 'string' )
      ret = left.dup
      ret = "||#{tag}->" + ret if $raccs_print_type
      re = get_quoted_re( left )

      sv, @in_block = @in_block, tag
      begin
        if s = reads(re) then
          ret << s
          break
        else
          ret << @line
        end
      end while next_line
      @in_block = sv

      ret << "<-#{tag}||" if $raccs_print_type
      ret
    end

    LEFT_TO_RIGHT = {
      '(' => ')',
      '{' => '}',
      '[' => ']',
      '<' => '>'
    }

    CACHE = {}

    def get_quoted_re( left )
      term = Regexp.quote( LEFT_TO_RIGHT[left] || left )
      CACHE[left] ||= /\A[^#{term}\\]*(?:\\.[^\\#{term}]*)*#{term}/
    end


    def scan_error!( msg )
      raise ScanError, "#{lineno}: #{msg}"
    end

    $raccs_print_type = false
          
  end

end   # module Racc
