# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".

require 'racc'
require 'racc/grammar'
require 'racc/parserfilegenerator'
require 'racc/sourcetext'
require 'stringio'

module Racc

  grammar = Grammar.define do
    g = self

    g.class = seq(:CLASS, :cname, many(:param), :RULE, :rules, option(:END))

    g.cname       = seq(:rubyconst) { |name|
                      @result.params.classname = name
                    } \
                  | seq(:rubyconst, "<", :rubyconst) { |c, _, s|
                      @result.params.classname = c
                      @result.params.superclass = s
                    }

    g.rubyconst   = separated_by1(:colon2, :SYMBOL) { |syms|
                      syms.map(&:to_s).join('::')
                    }

    g.colon2 = seq(':', ':')

    g.param       = seq(:CONV, many1(:convdef), :END) { |*|
                      #@grammar.end_convert_block   # FIXME
                    } \
                  | seq(:PRECHIGH, many1(:precdef), :PRECLOW) { |*|
                      @grammar.end_precedence_declaration(true)
                    } \
                  | seq(:PRECLOW, many1(:precdef), :PRECHIGH) { |*|
                      @grammar.end_precedence_declaration(false)
                    } \
                  | seq(:START, :symbol) { |_, sym|
                      @grammar.start_symbol = sym
                    } \
                  | seq(:TOKEN, :symbols) { |_, syms|
                      syms.each(&:should_be_terminal!)
                    } \
                  | seq(:OPTION, :options) { |_, syms|
                      # TODO: pull setting of options into a separate methods
                      syms.each do |opt|
                        case opt
                        when 'result_var'
                          @result.params.result_var = true
                        when 'no_result_var'
                          @result.params.result_var = false
                        when 'omit_action_call'
                          @result.params.omit_action_call = true
                        when 'no_omit_action_call'
                          @result.params.omit_action_call = false
                        else
                          raise CompileError, "unknown option: #{opt}"
                        end
                      end
                    } \
                  | seq(:EXPECT, :DIGIT) { |_, num|
                      @grammar.n_expected_srconflicts = num
                    }

    g.convdef     = seq(:symbol, :STRING) { |sym, code| sym.serialized = code }

    g.precdef     = seq(:LEFT, :symbols) { |_, syms|
                      @grammar.declare_precedence :Left, syms
                    } \
                  | seq(:RIGHT, :symbols) { |_, syms|
                      @grammar.declare_precedence :Right, syms
                    } \
                  | seq(:NONASSOC, :symbols) { |_, syms|
                      @grammar.declare_precedence :Nonassoc, syms
                    }

    g.symbols     = seq(:symbol) { |sym| [sym] } \
                  | seq(:symbols, :symbol) { |list, sym| list << sym } \
                  | seq(:symbols, "|")

    g.symbol      = seq(:SYMBOL) { |sym| @grammar.intern(sym) } \
                  | seq(:STRING) { |str| @grammar.intern(str) }

    g.options     = many(:SYMBOL) { |syms| syms.map(&:to_s) }

    g.rules       = option(:rules_core) { |list| add_rule_block(list) }

    # a set of grammar rules with the same LHS, like:
    # nonterminal: token1 token2 | token3 token4;
    # the terminating ; is optional
    g.rules_core  = seq(:symbol) { |sym| [sym] } \
                  | seq(:rules_core, :rule_item) { |list, i| list << i } \
                  | seq(:rules_core, ';') { |list, _|
                      add_rule_block(list)
                      list.clear
                    } \
                  | seq(:rules_core, ':') { |list, _|
                      # terminating ; was missing, so the previous token was
                      # actually a new LHS
                      next_target = list.pop
                      add_rule_block(list)
                      [next_target]
                    }

    g.rule_item   = seq(:symbol) \
                  | seq("|") { |_| OrMark.new(@scanner.lineno) } \
                  | seq("=", :symbol) { |_, sym| Prec.new(sym, @scanner.lineno) } \
                  | seq(:ACTION) { |src| UserAction.source_text(src) }
  end

  GrammarFileParser = grammar.parser_class

  if grammar.states.srconflict_exist?
    raise 'Racc boot script fatal: S/R conflict in build'
  end
  if grammar.states.rrconflict_exist?
    raise 'Racc boot script fatal: R/R conflict in build'
  end

  class GrammarFileParser   # reopen

    class Result
      def initialize(grammar, filename)
        @grammar = grammar
        @params = ParserFileGenerator::Params.new
        @params.filename = filename
      end

      attr_reader :grammar
      attr_reader :params
    end

    def GrammarFileParser.parse_file(filename)
      parse(File.read(filename), filename, 1)
    end

    def GrammarFileParser.parse(src, filename = '-', lineno = 1)
      new().parse(src, filename, lineno)
    end

    def initialize(debug_flags = DebugFlags.new)
      @yydebug = debug_flags.parse
    end

    def parse(src, filename = '-', lineno = 1)
      @filename = filename
      @lineno = lineno
      @scanner = GrammarFileScanner.new(src, @filename)
      @scanner.debug = @yydebug
      @grammar = Grammar.new
      @result = Result.new(@grammar, @filename)

      @embedded_action_seq = 0

      yyparse @scanner, :yylex

      parse_user_code

      @result.grammar.init
      @result
    end

    private

    def next_token
      @scanner.scan
    end

    def on_error(_tok, val, _values)
      fail CompileError, "#{location}: unexpected token #{val.inspect}"
    end

    def location
      "#{@filename}:#{@lineno - 1 + @scanner.lineno}"
    end

    def add_rule_block(list)
      return if list.empty?
      target = list.shift

      if target.is_a?(OrMark) || target.is_a?(UserAction) || target.is_a?(Prec)
        fail(CompileError, "#{target.lineno}: unexpected symbol #{target.name}")
      end

      split_array(list) { |obj| obj.is_a?(OrMark) }.each do |rule_items|
        sprec, rule_items = rule_items.partition { |obj| obj.is_a?(Prec) }
        if sprec.empty?
          add_rule(target, rule_items)
        elsif sprec.one?
          add_rule(target, rule_items, sprec.first.symbol)
        else
          fail(CompileError, "'=<prec>' used twice in one rule")
        end
      end
    end

    def split_array(array)
      chunk, index = [], 0
      results = [chunk]
      while index < array.size
        obj = array[index]
        if yield obj
          chunk = []
          results << chunk
        else
          chunk << obj
        end
        index += 1
      end
      results
    end

    def add_rule(target, list, prec = nil)
      if list.last.kind_of?(UserAction)
        act = list.pop
      else
        act = UserAction.empty
      end
      list.map! {|s| s.kind_of?(UserAction) ? embedded_action(s) : s }
      rule = Rule.new(target, list, act)
      rule.specified_prec = prec
      @grammar.add rule
    end

    def embedded_action(act)
      sym = @grammar.intern("@#{@embedded_action_seq += 1}".to_sym, true)
      @grammar.add Rule.new(sym, [], act)
      sym
    end

    # User Code Block

    def parse_user_code
      line = @scanner.lineno
      _, *blocks = *@scanner.epilogue.split(/^----/)
      blocks.each do |block|
        header, *body = block.lines.to_a
        label0, pathes = *header.sub(/\A-+/, '').split('=', 2)
        label = canonical_label(label0)
        (pathes ? pathes.strip.split(' ') : []).each do |path|
          add_user_code label, SourceText.new(File.read(path), path, 1)
        end
        add_user_code label, SourceText.new(body.join(''), @filename, line + 1)
        line += (1 + body.size)
      end
    end

    USER_CODE_LABELS = {
      'header'  => :header,
      'inner'   => :inner,
      'footer'  => :footer,
    }

    def canonical_label(src)
      label = src.to_s.strip.downcase.slice(/\w+/)
      unless USER_CODE_LABELS.key?(label)
        raise CompileError, "unknown user code type: #{label.inspect}"
      end
      label
    end

    def add_user_code(label, src)
      @result.params.send(USER_CODE_LABELS[label]).push src
    end

  end


  class GrammarFileScanner

    def initialize(str, filename = '-')
      @lines  = str.split(/\n|\r\n|\r/)
      @filename = filename
      @lineno = -1
      @line_head   = true
      @in_rule_blk = false
      @in_conv_blk = false
      @in_block = nil
      @epilogue = ''
      @debug = false
      next_line
    end

    attr_reader :epilogue

    def lineno
      @lineno + 1
    end

    attr_accessor :debug

    def yylex(&block)
      unless @debug
        yylex0(&block)
      else
        yylex0 do |sym, tok|
          $stderr.printf "%7d %-10s %s\n", lineno(), sym.inspect, tok.inspect
          yield [sym, tok]
        end
      end
    end

    private

    def yylex0
      begin
        until @line.empty?
          @line.sub!(/\A\s+/, '')
          if /\A\#/ =~ @line
            break
          elsif /\A\/\*/ =~ @line
            skip_comment
          elsif s = reads(/\A[a-zA-Z_]\w*/)
            yield [atom_symbol(s), s.to_sym]
          elsif s = reads(/\A\d+/)
            yield [:DIGIT, s.to_i]
          elsif ch = reads(/\A./)
            case ch
            when '"', "'"
              yield [:STRING, eval(scan_quoted(ch))]
            when '{'
              lineno = lineno()
              yield [:ACTION, SourceText.new(scan_action(), @filename, lineno)]
            else
              if ch == '|'
                @line_head = false
              end
              yield [ch, ch]
            end
          else
          end
        end
      end while next_line()
      yield nil
    end

    def next_line
      @lineno += 1
      @line = @lines[@lineno]
      if not @line or /\A----/ =~ @line
        # class block is over, user code blocks follow
        @epilogue = @lines.join("\n")
        @lines.clear
        @line = nil
        if @in_block
          @lineno -= 1
          scan_error!(sprintf('unterminated %s', @in_block))
        end
        false
      else
        @line.sub!(/(?:\n|\r\n|\r)\z/, '')
        @line_head = true
        true
      end
    end

    ReservedWord = {
      'right'    => :RIGHT,
      'left'     => :LEFT,
      'nonassoc' => :NONASSOC,
      'preclow'  => :PRECLOW,
      'prechigh' => :PRECHIGH,
      'token'    => :TOKEN,
      'convert'  => :CONV,
      'options'  => :OPTION,
      'start'    => :START,
      'expect'   => :EXPECT,
      'class'    => :CLASS,
      'rule'     => :RULE,
      'end'      => :END
    }

    def atom_symbol(token)
      if token == 'end'
        symbol = :END
        @in_conv_blk = false
        @in_rule_blk = false
      else
        if @line_head and not @in_conv_blk and not @in_rule_blk
          symbol = ReservedWord[token] || :SYMBOL
        else
          symbol = :SYMBOL
        end
        case symbol
        when :RULE then @in_rule_blk = true
        when :CONV then @in_conv_blk = true
        end
      end
      @line_head = false
      symbol
    end

    def skip_comment
      @in_block = :comment
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
      @in_block = :action
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
      (!pre || /[a-zA-Z_0-9]/n !~ pre[-1,1]) &&
          !post.empty? && /\A[\s\=]/n !~ post
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
end
