module Racc
  # DSL for defining a grammar in code, rather than using a grammar file
  module DSL
    def self.define_grammar(&block)
      env = DefinitionEnv.new
      env.instance_eval(&block)
      env.grammar
    end

    # Methods are DSL 'keywords' which can be used in a `define_grammar` block
    #
    # Key method is `#seq`, which creates a `Rule`
    # (`Rule` objects can be combined using `#|`, similar to how alternative
    # derivations for a non-terminal are separated by | in a BNF grammar)
    #
    # Other key method is `#method_missing`, which is used to register rules:
    #
    #     self.nonterminal_name = seq(:token, :another_token) | seq(:something_else)
    #
    class DefinitionEnv
      def initialize
        @grammar = Grammar.new
        @seqs = Hash.new(0)
        @delayed = []
      end

      def grammar
        flush_delayed
        @grammar.finished!
        @grammar
      end

      # Intercept calls to `self.non_terminal = ...`, and use them to register
      # a new rule
      def method_missing(mid, *args, &block)
        unless mid.to_s[-1, 1] == '='
          super # raises NoMethodError
        end
        target = @grammar.intern(mid.to_s.chop.intern)
        unless args.size == 1
          fail ArgumentError, "too many arguments for #{mid} (#{args.size} for 1)"
        end
        _add(target, args.first)
      end

      # We just received a call to `self.nonterminal = definition`
      # But when we were executing that "definition", we didn't know what the
      # nonterminal on the LHS would be
      # Depending on the DSL method(s) which were used in the "definition",
      # `rhs` may be:
      # - A "placeholder" target symbol, which should be replaced with the
      #   "real" target in all the rules which the definition created
      # - A `Rule`, whose target we didn't know at the time of definition.
      #   Its target will be `nil` right now; fix that up.
      def _add(target, rhs)
        case rhs
        when Sym
          @delayed.each do |rule|
            rule.replace(rhs, target) if rule.target == rhs
          end
          @grammar.delete_symbol(rhs)
        else
          rhs.each_rule do |rule|
            rule.target = target
            @grammar.add(rule)
          end
        end
        flush_delayed
      end

      def _delayed_add(rule)
        @delayed.push(rule)
      end

      def _added?(sym)
        @grammar.added?(sym) || @delayed.detect { |r| r.target == sym }
      end

      def flush_delayed
        return if @delayed.empty?
        @delayed.each do |rule|
          @grammar.add rule
        end
        @delayed.clear
      end

      # Basic method for creating a new `Rule`.
      def seq(*list, &block)
        Rule.new(nil, list.map { |x| _intern(x) }, UserAction.proc(block))
      end

      # Create a null `Rule` (one with an empty RHS)
      def null(&block)
        seq(&block)
      end

      # Create a `Rule` which can either be null (like an empty RHS in a BNF grammar),
      # in which case the action will return `default`, or which can match a single
      # `sym`.
      def option(sym, default = nil, &block)
        _defmetasyntax('option', _intern(sym), block) do |_target|
          seq { default } | seq(sym)
        end
      end

      # Create a `Rule` which matches 0 or more instance of `sym` in a row.
      def many(sym, &block)
        _defmetasyntax('many', _intern(sym), block) do |target|
          seq { [] }\
        | seq(target, sym) { |list, x| list.push x; list }
        end
      end

      # Create a `Rule` which matches 1 or more instances of `sym` in a row.
      def many1(sym, &block)
        _defmetasyntax('many1', _intern(sym), block) do |target|
          seq(sym) { |x| [x] }\
        | seq(target, sym) { |list, x| list.push x; list }
        end
      end

      # Create a `Rule` which matches 0 or more instances of `sym`, separated
      # by `sep`.
      def separated_by(sep, sym, &block)
        option(separated_by1(sep, sym), [], &block)
      end

      # Create a `Rule` which matches 1 or more instances of `sym`, separated
      # by `sep`.
      def separated_by1(sep, sym, &block)
        _defmetasyntax('separated_by1', _intern(sym), block) do |target|
          seq(sym) { |x| [x] }\
        | seq(target, sep, sym) { |list, _, x| list.push x; list }
        end
      end

      def _intern(x)
        case x
        when Symbol, String
          @grammar.intern(x)
        when Racc::Sym
          x
        else
          fail TypeError, "wrong type #{x.class} (expected Symbol/String/Racc::Sym)"
        end
      end

      private

      # the passed block will define a `Rule` (which may be chained with
      # 'alternative' `Rule`s)
      # make all of those rules reduce to a placeholder nonterminal,
      # executing `action` when they do so,
      # and return the newly generated placeholder
      #
      # (when the placeholder is associated with a "real" nonterminal using the
      # `self.non_terminal = ...` syntax, we will go through all the generated
      # rules and rewrite the placeholder to the "real" nonterminal)
      #
      def _defmetasyntax(type, id, action, &block)
        if action
          idbase = :"#{type}@#{id}-#{@seqs[type] += 1}"
          _regist(:"#{idbase}-core", &block)
          _wrap(idbase, :"#{idbase}-core", action)
        else
          _regist(:"#{type}@#{id}", &block)
        end
      end

      def _regist(target)
        sym = @grammar.intern(target)
        unless _added?(sym)
          yield(target).each_rule do |rule|
            rule.target = sym
            _delayed_add(rule)
          end
        end
        sym
      end

      # create a rule which reduces wrapped -> wrapper and executes an
      # action at the same time
      # (this is a way to make sure an action is executed everytime a
      # reduction is done using a particular generated rule)
      def _wrap(wrapper, wrapped, block)
        wrapped = @grammar.intern(wrapped)
        wrapper = @grammar.intern(wrapper)
        _delayed_add Rule.new(wrapper, [wrapped], UserAction.proc(block))
        wrapper
      end
    end
  end
end
