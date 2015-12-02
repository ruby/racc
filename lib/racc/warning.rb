require 'racc/color'
require 'racc/simulated_parse_context'

module Racc
  include Racc::Color

  class Warning < Struct.new(:type, :title, :details)
    def initialize(type, title, details = nil)
      super
    end

    def to_s
      msg = violet('Warning: ') << bright(title)
      msg << "\n" << details if details
      msg
    end

    # Would this warning contain more details in verbose mode?
    def verbose_details?
      type == :sr_conflict || type == :rr_conflict
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
        "#{'s' unless @sym.heads.one?}:\n" <<
        @sym.heads.map { |ptr| ptr.rule.to_s }.join("\n")
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

    class SRConflict < Warning
      def initialize(conflict, grammar, verbose)
        @grammar = grammar
        @path    = conflict.state.path
        @srules  = conflict.srules
        @rrule   = conflict.rrule
        @sym     = conflict.symbol
        @verbose = verbose
      end

      def title
        "Shift/reduce conflict on #{@sym}," <<
          (@path.reject(&:hidden).empty? ?
            ' at the beginning of the parse.' :
            ' after the following input:')
      end

      def details
        if @path.reject(&:hidden).empty?
          result = ''
        else
          result = @path.reject(&:hidden).map(&:to_s).join(' ') << "\n"
        end

        result << "\nThe following rule#{'s' unless @srules.one?} " \
          "direct#{'s' if @srules.one?} me to shift:\n" <<
          @srules.map { |ptr| ptr.rule.to_s }.join("\n") <<
          "\nThe following rule directs me to reduce:\n" <<
          @rrule.to_s

        if @verbose
          scontext = SimulatedParseContext.from_path(@grammar, @path).shift!(@sym)
          result << "\n\nAfter shifting #{@sym}, one path to a successful " \
            "parse would be:\n" << scontext.path_to_success.map(&:to_s).join(' ')

          rcontext = SimulatedParseContext.from_path(@grammar, @path)
                                          .reduce!(@rrule.target).consume!(@sym)
          result << ((catch :dead_end do
            "\n\nAfter reducing to #{@rrule.target}, one path to a " \
            "successful parse would be:\n" <<
            rcontext.path_to_success.unshift(@sym).map(&:to_s).join(' ')
          end) || "\n\nI can't see any way that reducing to " \
            "#{@rrule.target} could possibly lead to a successful parse " \
            'from this situation. But maybe if this parser state was ' \
            "reached through a different input sequence, it could. I'm " \
            'just a LALR parser generator and I can be pretty daft sometimes.')
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
        @path    = conflict.state.path
        @sym     = conflict.symbol
        @rules   = conflict.rules
        @verbose = verbose
      end

      def title
        "Reduce/reduce conflict on #{@sym}," <<
          (@path.reject(&:hidden).empty? ?
            ' at the beginning of the parse.' :
            ' after the following input:')
      end

      def details
        if @path.reject(&:hidden).empty?
          result = ''
        else
          result = @path.reject(&:hidden).map(&:to_s).join(' ') << "\n"
        end

        result << "\nIt is possible to reduce by " \
               "#{@rules.size == 2 ? 'either' : 'any'} of these rules:\n" <<
               @rules.map(&:to_s).join("\n")

        if @verbose
          targets = @rules.map(&:target).uniq
          if targets.size > 1
            targets.each do |target|
              rcontext = SimulatedParseContext.from_path(@grammar, @path)
                                              .reduce!(target).consume!(@sym)
              result << ((catch :dead_end do
                "\n\nAfter reducing to #{target}, one path to a " \
                "successful parse would be:\n" <<
                rcontext.path_to_success.unshift(@sym).map(&:to_s).join(' ')
              end) || "\n\nI can't see any way that reducing to " \
                "#{target} could possibly lead to a successful parse " \
                'from this situation. But maybe if this parser state was ' \
                "reached through a different input sequence, it could. I'm " \
                'just a LALR parser generator and I can be pretty daft sometimes.')
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