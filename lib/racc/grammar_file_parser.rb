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
require 'racc/source'
require 'racc/dsl'

module Racc

  grammar = DSL.define_grammar do
    g = self

    g.class = seq(:CLASS, :cname, many(:param), option(:rules), option(:END))

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
                      syms.each(&:declared_as_terminal!)
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

    g.symbol      = seq(:SYMBOL) { |(sym, range)| [@grammar.intern(sym, false), range] } \
                  | seq(:STRING) { |(str, range)| [@grammar.intern(str, false), range] }

    g.options     = many(:SYMBOL) { |syms| syms.map(&:first).map(&:to_s) }

    g.rules       = seq(:RULE, option(:rules_core) { |list| add_rule_block(list) })

    # a set of grammar rules with the same LHS, like:
    # nonterminal: token1 token2 | token3 token4;
    # the terminating ; is optional
    g.rules_core  = seq(:symbol) { |sym| [sym] } \
                  | seq(:rules_core, :rule_item) { |list, i| list << i } \
                  | seq(:rules_core, ';') { |list, _|
                      add_rule_block(list)
                      list.clear
                    } \
                  | seq(:rules_core, ':') { |list, (_, colon_range)|
                      # terminating ; may have been missing, in which case the
                      # previous token was actually a new LHS
                      # if it wasn't missing, we will just call add_rule_block
                      # with an empty list, which won't do anything
                      next_target = list.pop
                      add_rule_block(list)
                      [next_target, [':', colon_range]]
                    }

    g.rule_item   = seq(:symbol) \
                  | seq("|") { |(_, range)|
                      [OrMark.new(range.lineno), range]
                    } \
                  | seq("=", :symbol) { |(_, range1), (sym, range2)|
                      range = Source::Range.new(@file, range1.from, range2.to)
                      [Prec.new(sym, range), range]
                    } \
                  | seq(:ACTION) { |(range)|
                      [UserAction.source_text(range, range.lineno), range]
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
      def initialize(grammar, file)
        @grammar = grammar
        @params = ParserFileGenerator::Params.new
        @params.file = file
      end

      attr_reader :grammar
      attr_reader :params
    end

    def GrammarFileParser.parse_file(filename)
      new.parse(File.read(filename), filename)
    end

    def parse(src, filename = '-')
      @file    = Source::Buffer.new(filename, src)
      @scanner = GrammarFileScanner.new(@file)
      @grammar = Grammar.new
      @result  = Result.new(@grammar, @file)
      @embedded_action_seq = 0

      yyparse @scanner, :yylex
      parse_user_code

      @grammar.finished!
      @result
    end

    private

    def on_error(_tok, val, _values)
      fail(CompileError, "#{@scanner.lineno}: unexpected token #{val[0].inspect}")
    end

    def add_rule_block(list)
      return if list.empty?
      target, target_range = *list.shift
      target_range.highlights << Source::Highlight.new(target, 0,
                                   target_range.to - target_range.from)

      if target.is_a?(OrMark) || target.is_a?(UserAction) || target.is_a?(Prec)
        fail(CompileError, "#{target.lineno}: unexpected symbol #{target.name}")
      end

      if list.empty? # only derivation rule is null
        add_rule(target, [], target_range)
        return
      end

      # record highlights which will be used when printing out rules
      block_end   = list.last[1].to
      block_end  += 1 if list.last[0].is_a?(UserAction) # show terminating }
      block_range = Source::Range.new(@file, target_range.from, block_end)
      highlights  = list
                      .select { |obj, r| obj.is_a?(Sym) || obj.is_a?(Prec) }
                      .map { |obj, r| Source::Highlight.new(obj,
                                                            r.from - block_range.from,
                                                            r.to - block_range.from) }
      block_range.highlights = highlights.unshift(target_range.highlights[0])

      groups = split_array(list) { |obj, r| obj.is_a?(OrMark) }
      groups.each do |rule_items|
        sprec, rule_items = rule_items.partition { |obj, r| obj.is_a?(Prec) }
        items, ranges     = *rule_items.transpose

        if items
          items.shift # drop OrMark or ':'
          ranges.shift unless ranges.one?
        end

        if ranges
          range = block_range.slice(ranges.map(&:from).min - block_range.from,
                                    ranges.map(&:to).max   - block_range.from)
          range = Source::SparseLines.new(block_range, [target_range.lines, range.lines])
        end

        if sprec.empty?
          add_rule(target, items || [], range)
        elsif sprec.one?
          add_rule(target, items || [], range, sprec[0][0].symbol)
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
          chunk = [obj]
          results << chunk
        else
          chunk << obj
        end
        index += 1
      end
      results
    end

    def add_rule(target, list, range, prec = nil)
      if list.last.kind_of?(UserAction)
        act = list.pop
      else
        act = UserAction.empty
      end
      list.map! { |s| s.kind_of?(UserAction) ? embedded_action(s, target) : s }
      @grammar.add(Rule.new(target, list, act, range, prec))
    end

    def embedded_action(act, target)
      sym = @grammar.intern("@action#{@embedded_action_seq += 1}".to_sym, true)
      @grammar.add(Rule.new(sym, [], act))
      sym
    end

    # User Code Block

    def parse_user_code
      epilogue = @scanner.epilogue
      return unless epilogue.text
      epilogue.text.scan(/^----([^\n\r]*)(?:\n|\r\n|\r)(.*?)(?=^----|\Z)/m) do
        label = canonical_label($~[1])
        range = epilogue.slice($~.begin(2), $~.end(2))
        add_user_code(label, range)
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
