require 'racc/color'

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
  end
end