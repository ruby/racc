#
# $Id: 
#
# Copyright (c) 1999-2005 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".
#

require 'racc/exception'

module Racc

  class GrammarFileScanner

    def initialize(str)
      @lines  = str.split(/\n|\r\n|\r/)
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

    attr_accessor :debug

    def scan
      result = do_scan()
      if @debug
        $stderr.printf "%7d %-10s %s\n",
                       lineno(), result[0].inspect, result[1].inspect
      end
      result
    end

    def do_scan
      begin
        until @line.empty?
          @line.sub!(/\A\s+/, '')

          if /\A\#/ =~ @line
            break

          elsif /\A\/\*/ =~ @line
            skip_comment

          elsif s = reads(/\A[a-zA-Z_]\w*/)
            return check_atom(s)

          elsif s = reads(/\A\d+/)
            return :DIGIT, s.to_i

          elsif ch = reads(/\A./)
            case ch
            when '"', "'"
              return :STRING, eval(scan_quoted(ch))
            when '{'
              return :ACTION, [scan_action(), lineno()]
            else
              if ch == '|'
                @line_head = false
              end
              return ch, ch
            end

          else
            ;
          end
        end
      end while next_line()

      return false, '$'
    end

    private

    def next_line
      @lineno += 1
      @line = @lines[@lineno]

      if not @line or /\A----/ =~ @line
        @lines.clear
        @line = nil
        if @in_block
          @lineno -= 1
          scan_error! sprintf('unterminated %s', @in_block)
        end

        false
      else
        @line.sub!(/(?:\n|\r\n|\r)\z/, '')
        @line_head = true
        true
      end
    end

    ReservedWord = {
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

    def check_atom(cur)
      if cur == 'end'
        symbol = :XEND
        @in_conv_blk = false
        @in_rule_blk = false
      else
        if @line_head and not @in_conv_blk and not @in_rule_blk
          symbol = ReservedWord[cur] || :XSYMBOL
        else
          symbol = :XSYMBOL
        end
        case symbol
        when :XRULE then @in_rule_blk = true
        when :XCONV then @in_conv_blk = true
        end
      end
      @line_head = false

      [symbol, cur.intern]
    end

    def skip_comment
      @in_block = 'comment'
      until m = /\*\//.match(@line)
        next_line
      end
      @line = m.post_match
      @in_block = nil
    end

    $raccs_print_type = false

    def scan_action
      buf = ''
      nest = 1
      pre = nil

      @in_block = 'action'

      begin
        pre = nil
        if s = reads(/\A\s+/)
          # does not set 'pre'
          buf << s
        end

        until @line.empty?
          if s = reads(/\A[^'"`{}%#\/\$]+/)
            buf << (pre = s)
            next
          end

          case ch = read(1)
          when '{'
            nest += 1
            buf << (pre = ch)

          when '}'
            nest -= 1
            if nest == 0
              @in_block = nil
              return buf
            end
            buf << (pre = ch)

          when '#'   # comment
            buf << ch << @line
            break

          when "'", '"', '`'
            buf << (pre = scan_quoted(ch))

          when '%'
            if literal_head? pre, @line
              # % string, regexp, array
              buf << ch
              case ch = read(1)
              when /[qQx]/n
                buf << ch << (pre = scan_quoted(read(1), '%string'))
              when /wW/n
                buf << ch << (pre = scan_quoted(read(1), '%array'))
              when /s/n
                buf << ch << (pre = scan_quoted(read(1), '%symbol'))
              when /r/n
                buf << ch << (pre = scan_quoted(read(1), '%regexp'))
              when /[a-zA-Z0-9= ]/n   # does not include "_"
                scan_error! "unknown type of % literal '%#{ch}'"
              else
                buf << (pre = scan_quoted(ch, '%string'))
              end
            else
              # operator
              buf << '||op->' if $raccs_print_type
              buf << (pre = ch)
            end

          when '/'
            if literal_head? pre, @line
              # regexp
              buf << (pre = scan_quoted(ch, 'regexp'))
            else
              # operator
              buf << '||op->' if $raccs_print_type
              buf << (pre = ch)
            end

          when '$'   # gvar
            buf << ch << (pre = read(1))

          else
            raise 'racc: fatal: must not happen'
          end
        end

        buf << "\n"
      end while next_line()

      raise 'racc: fatal: scan finished before parser finished'
    end

    def literal_head?(pre, post)
      (not pre or not /[a-zA-Z_0-9]/n =~ pre[-1,1]) and
          not post.empty? and not /\A[\s\=]/n =~ post
    end

    def read(len)
      s = @line[0, len]
      @line = @line[len .. -1]
      s
    end

    def reads(re)
      m = re.match(@line) or return nil
      @line = m.post_match
      m[0]
    end

    def scan_quoted(left, tag = 'string')
      buf = left.dup
      buf = "||#{tag}->" + buf if $raccs_print_type
      re = get_quoted_re(left)

      sv, @in_block = @in_block, tag
      begin
        if s = reads(re)
          buf << s
          break
        else
          buf << @line
        end
      end while next_line()
      @in_block = sv

      buf << "<-#{tag}||" if $raccs_print_type
      buf
    end

    LEFT_TO_RIGHT = {
      '(' => ')',
      '{' => '}',
      '[' => ']',
      '<' => '>'
    }

    CACHE = {}

    def get_quoted_re(left)
      term = Regexp.quote(LEFT_TO_RIGHT[left] || left)
      CACHE[left] ||= /\A[^#{term}\\]*(?:\\.[^\\#{term}]*)*#{term}/
    end

    def scan_error!(msg)
      raise CompileError, "#{lineno()}: #{msg}"
    end

  end

end   # module Racc
