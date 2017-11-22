require 'racc/color'
require 'racc/simulated_automaton'

module Racc
  include Racc::Color

  # Categorize warnings according to entity which warning relates to
  # This can be used to avoid issuing a general warning when a more specific
  # and informative warning has already been registered
  class Warnings
    include Enumerable

    def initialize
      @rules   = Hash.new { |h,k| h[k] = [] }
      @states  = Hash.new { |h,k| h[k] = [] }
      @symbols = Hash.new { |h,k| h[k] = [] }
    end

    def add_for_rule(rule, warning)
      @rules[rule] << warning
    end

    def add_for_state(state, warning)
      @states[state] << warning
    end

    def add_for_symbol(symbol, warning)
      @symbols[symbol] << warning
    end

    def each(&block)
      @symbols.keys.sort_by(&:ident).each { |k| @symbols[k].each(&block) }
      @rules.keys.sort_by(&:ident).each   { |k| @rules[k].each(&block) }
      @states.keys.sort_by(&:ident).each  { |k| @states[k].each(&block) }
    end

    def for_rule(rule)
      @rules[rule]
    end

    def for_state(state)
      @states[state]
    end

    def for_symbol(symbol)
      @symbols[symbol]
    end
  end

  class Warning < Struct.new(:type, :title, :details)
    def initialize(type, title, details = nil)
      super
    end

    def to_s
      msg = violet('Warning: ') + bright(title)
      msg << "\n" << details if details
      msg
    end

    # Would this warning contain more details in verbose mode?
    def verbose_details?
      type == :sr_conflict || type == :rr_conflict
    end

    class UnusedTerminal < Warning
      def initialize(sym)
        @sym = sym
      end

      def title
        "Useless terminal #{@sym} does not appear on the right side of any rule"
      end

      def type
        :useless_terminal
      end
    end

    class UnusedNonterminal < Warning
      def initialize(sym)
        @sym = sym
      end

      def title
        "Useless nonterminal #{@sym} does not appear on the right side of " \
          "any rule, neither is it the start symbol"
      end

      def type
        :useless_nonterminal
      end
    end

    class InfiniteLoop < Warning
      def initialize(sym)
        @sym = sym
      end

      def title
        "Useless nonterminal #{@sym} can never be produced from a finite sequence of tokens"
      end

      def details
        "Its derivation rule#{'s all' unless @sym.heads.one?} contain" \
        "#{'s' if @sym.heads.one?} #{'an ' if @sym.heads.one?}infinite loop" \
        "#{'s' unless @sym.heads.one?}:\n" +
        @sym.heads.map { |ptr| ptr.rule.to_s }.join("\n")
      end

      def type
        :useless_nonterminal
      end
    end

    class UnreachableNonterminal < Warning
      def initialize(sym)
        @sym = sym
      end

      def title
        "Useless nonterminal #{sym} cannot be part of a valid parse tree, " \
          'since there is no sequence of reductions from it to the start symbol.'
      end

      def details
        "It can only reduce to: #{sym.reachable.map(&:to_s).join(', ')}"
      end

      def type
        :useless_nonterminal
      end
    end

    class UselessPrecedence < Warning
      def initialize(rule)
        @rule = rule
      end

      def title
        'The explicit precedence declaration on this rule does not resolve ' \
        'any conflicts and can be removed:'
      end

      def details
        @rule.to_s
      end

      def type
        :useless_prec
      end
    end

    class RuleAlwaysOverridden < Warning
      def initialize(rule)
        @rule = rule
      end

      def title
        'This rule will never be used due to low precedence:'
      end

      def details
        @rule.to_s << "\n\n" << @rule.overridden_by.group_by do |token, rules|
          rules
        end.map do |rules, tokens|
          tokens = tokens.map(&:first)
          connective = if tokens.one?
            ''
          elsif tokens.size == 2
            'either '
          else
            'any of '
          end

          "When the next token is #{connective}#{Racc.to_sentence(tokens, 'or')}" \
          ", it is overridden by #{rules.one? ? 'this' : 'these'} " \
          "higher-precedence rule#{'s' unless rules.one?}:\n" +
          Source::SparseLines.render(rules.map(&:source))
        end.join("\n\n")
      end

      def type
        :useless_rule
      end
    end

    class SRConflict < Warning
      def initialize(conflict, grammar, verbose)
        @grammar = grammar
        @path    = conflict.state.shortest_summarized_path
        @srules  = conflict.srules
        @rrule   = conflict.rrule
        @sym     = conflict.symbol
        @verbose = verbose
      end

      def title
        "Shift/reduce conflict on #{@sym}," +
          (@path.reject(&:hidden?).empty? ?
            ' at the beginning of the parse.' :
            ' after the following input:')
      end

      def details
        if @path.reject(&:hidden?).empty?
          result = String.new
        else
          result = @path.reject(&:hidden?).map(&:to_s).join(' ') << "\n"
        end

        result << "\nThe following rule#{'s' unless @srules.one?} " \
          "direct#{'s' if @srules.one?} me to shift:\n" <<
          @srules.map { |ptr| ptr.rule.to_s }.join("\n") <<
          "\nThe following rule directs me to reduce:\n" <<
          @rrule.to_s

        if @verbose
          sauto = SimulatedAutomaton.from_path(@grammar, @path).consume!(@sym)
          result << "\n\nAfter shifting #{@sym}, one path to a successful " \
            "parse would be:\n" << sauto.path_to_success.map(&:to_s).join(' ')

          rauto = SimulatedAutomaton.from_path(@grammar, @path)
                                    .reduce_by!(@rrule).consume!(@sym)
          path  = rauto.path_to_success
          if path
            result << "\n\nAfter reducing to #{@rrule.target}, one path to a " \
              "successful parse would be:\n" << path.unshift(@sym).map(&:to_s).join(' ')
          else
            result << "\n\nI can't see any way that reducing to " \
              "#{@rrule.target} could possibly lead to a successful parse " \
              'from this situation. But maybe if this parser state was ' \
              "reached through a different input sequence, it could. I'm " \
              'just a LALR parser generator and I can be pretty daft sometimes.'
          end
        end

        result
      end

      def type
        :sr_conflict
      end
    end

    class RRConflict < Warning
      def initialize(conflict, grammar, verbose)
        @grammar = grammar
        @path    = conflict.state.shortest_summarized_path
        @sym     = conflict.symbol
        @rules   = conflict.rules
        @verbose = verbose
      end

      def title
        "Reduce/reduce conflict on #{@sym}," +
          (@path.reject(&:hidden?).empty? ?
            ' at the beginning of the parse.' :
            ' after the following input:')
      end

      def details
        if @path.reject(&:hidden?).empty?
          result = String.new
        else
          result = @path.reject(&:hidden?).map(&:to_s).join(' ') << "\n"
        end

        result << "\nIt is possible to reduce by " \
               "#{@rules.size == 2 ? 'either' : 'any'} of these rules:\n" <<
               @rules.map(&:to_s).join("\n")

        if @verbose
          targets = @rules.group_by(&:target)
          if targets.size > 1
            targets.each do |target, rules|
              rauto = SimulatedAutomaton.from_path(@grammar, @path)
                                        .reduce_by!(rules.first).consume!(@sym)
              path  = rauto.path_to_success
              if path
                result << "\n\nAfter reducing to #{target}, one path to a " \
                  "successful parse would be:\n" <<
                  path.unshift(@sym).map(&:to_s).join(' ')
              else
                result << "\n\nI can't see any way that reducing to " \
                  "#{target} could possibly lead to a successful parse " \
                  'from this situation. But maybe if this parser state was ' \
                  "reached through a different input sequence, it could. I'm " \
                  'just a LALR parser generator and I can be pretty daft sometimes.'
              end
            end
          end
        end

        result
      end

      def type
        :rr_conflict
      end
    end
  end
end
