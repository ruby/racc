# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".

require 'racc'
require 'racc/grammar'
require 'racc/grammar_file_scanner'
require 'racc/parser_file_generator'
require 'racc/source_text'

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
                      syms.map(&:first).map(&:to_s).join('::')
                    }

    g.colon2 = seq(':', ':')

    g.param       = seq(:CONV, many1(:convdef), :END) \
                  | seq(:PRECHIGH, many1(:precdef), :PRECLOW) { |*|
                      @grammar.end_precedence_declaration(true)
                    } \
                  | seq(:PRECLOW, many1(:precdef), :PRECHIGH) { |*|
                      @grammar.end_precedence_declaration(false)
                    } \
                  | seq(:START, :symbol) { |_, (sym)|
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
                        else
                          raise CompileError, "unknown option: #{opt}"
                        end
                      end
                    } \
                  | seq(:EXPECT, :DIGIT) { |_, (num)|
                      @grammar.n_expected_srconflicts = num
                    }

    g.convdef     = seq(:symbol, :STRING) { |(sym), (code)|
                      sym.serialized = code
                    }

    g.precdef     = seq(:LEFT, :symbols) { |_, syms|
                      @grammar.declare_precedence :Left, syms
                    } \
                  | seq(:RIGHT, :symbols) { |_, syms|
                      @grammar.declare_precedence :Right, syms
                    } \
                  | seq(:NONASSOC, :symbols) { |_, syms|
                      @grammar.declare_precedence :Nonassoc, syms
                    }

    g.symbols     = seq(:symbol) { |(sym)| [sym] } \
                  | seq(:symbols, :symbol) { |list, (sym)| list << sym } \
                  | seq(:symbols, "|")

    g.symbol      = seq(:SYMBOL) { |(sym, lines)| [@grammar.intern(sym, false), lines] } \
                  | seq(:STRING) { |(str, lines)| [@grammar.intern(str, false), lines] }

    g.options     = many(:SYMBOL) { |syms| syms.map(&:first).map(&:to_s) }

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
                  | seq("|") { |(_, lines)|
                      [OrMark.new(lines.first), lines]
                    } \
                  | seq("=", :symbol) { |_, (sym, lines)|
                      [Prec.new(sym, lines.first), lines]
                    } \
                  | seq(:ACTION) { |(src, lines)|
                      [UserAction.source_text(src, lines.first), lines]
                    }
  end

  GrammarFileParser = grammar.parser_class

  if grammar.sr_conflicts.any?
    raise 'Racc boot script fatal: S/R conflict in build'
  end
  if grammar.rr_conflicts.any?
    raise 'Racc boot script fatal: R/R conflict in build'
  end

  class GrammarFileParser # reopen
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
      new.parse(src, filename, lineno)
    end

    def parse(src, filename = '-', lineno = 1)
      @filename = filename
      @lineno = lineno
      @scanner = GrammarFileScanner.new(src, @filename)
      @grammar = Grammar.new(filename)
      @result = Result.new(@grammar, @filename)
      @embedded_action_seq = 0

      yyparse @scanner, :yylex
      parse_user_code

      @result.grammar.finished!
      @result
    end

    private

    def on_error(_tok, val, _values)
      fail CompileError, "#{location}: unexpected token #{val.inspect}"
    end

    def location
      "#{@filename}:#{@lineno - 1 + @scanner.lineno}"
    end

    def add_rule_block(list)
      return if list.empty?

      items, lines = *list.transpose
      target = items.shift

      line_range = (lines.map(&:first).min)..(lines.map(&:last).max)

      if target.is_a?(OrMark) || target.is_a?(UserAction) || target.is_a?(Prec)
        fail(CompileError, "#{target.lineno}: unexpected symbol #{target.name}")
      end

      split_array(items) { |obj| obj.is_a?(OrMark) }.each do |rule_items|
        sprec, rule_items = rule_items.partition { |obj| obj.is_a?(Prec) }
        if sprec.empty?
          add_rule(target, rule_items, line_range)
        elsif sprec.one?
          add_rule(target, rule_items, line_range, sprec.first.symbol)
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

    def add_rule(target, list, line_range, prec = nil)
      if list.last.kind_of?(UserAction)
        act = list.pop
      else
        act = UserAction.empty
      end
      list.map! { |s| s.kind_of?(UserAction) ? embedded_action(s, target) : s }
      @grammar.add(Rule.new(target, list, act, line_range, prec))
    end

    def embedded_action(act, target)
      sym = @grammar.intern("@#{@embedded_action_seq += 1}".to_sym, true)
      @grammar.add(Rule.new(sym, [], act))
      sym.hidden = true
      sym
    end

    # User Code Block

    def parse_user_code
      line = @scanner.lineno
      _, *blocks = *@scanner.epilogue.split(/^----/)
      blocks.each do |block|
        header, *body = block.lines.to_a
        label = canonical_label(header.sub(/\A-+/, ''))
        add_user_code(label, SourceText.new(body.join(''), @filename, line + 1))
        line += (1 + body.size)
      end
    end

    USER_CODE_LABELS = %w(header inner footer)

    def canonical_label(src)
      label = src.to_s.strip.downcase.slice(/\w+/)
      unless USER_CODE_LABELS.include?(label)
        raise CompileError, "unknown user code type: #{label.inspect}"
      end
      label
    end

    def add_user_code(label, src)
      @result.params.send(label.to_sym).push(src)
    end
  end
end
