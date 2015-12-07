require 'racc/state'
require 'racc/directed_graph'
require 'set'

module Racc
  class SimulatedAutomaton
    def self.from_path(grammar, path)
      path.each_with_object(self.new(grammar.states)) do |sym, automaton|
        if sym.terminal?
          automaton.consume!(sym)
        else
          automaton.goto!(sym)
        end
      end
    end

    def initialize(states)
      @states = states
      @state  = states.first
      @sstack = []
      @error  = false
    end

    attr_reader :state

    def stack
      @sstack
    end

    def error?
      @error
    end

    # consuming a terminal may set off a series of reduces before the terminal
    # is shifted
    def consume!(token)
      return self if @error

      action = @state.action[token] || @state.defact
      case action
      when Shift
        @sstack.push(@state)
        @state = action.goto_state
        shifted(token)
      when Reduce
        reduce_by!(action.rule)
        consume!(token)
      when Accept
        done
      when Error
        @error = true
        error
      else
        raise "Illegal action type: #{action.class}"
      end

      self
    end

    def goto!(nt)
      @sstack.push(@state)
      @state = @state.gotos[nt].to_state
      goto(nt)
      self
    end

    def reduce_by!(rule)
      rule.symbols.size.times { @state = @sstack.pop }
      reduced(rule.target)
      goto!(rule.target)
    end

    # Callbacks; can be overridden

    def shifted(symbol)
    end

    def reduced(nt)
    end

    def goto(nt)
    end

    def done
    end

    def error
    end

    def path_to_success(traversed = Set.new)
      # Find the shortest series of terminals/reduce operations which will take
      # us to the accept state
      return []  if @state.ident == 1
      return nil if @error

      # Don't go into an infinite loop exploring the same states
      return unless traversed.add?(@sstack + [@state])

      # The state stack will guide us
      # How many symbols could we reduce the stack size by for each reduce
      # reachable from this state?
      core = @state.core.group_by { |ptr| [ptr.target, ptr.index] }

      core.map do |(target, offset), ptrs|
        ptr = ptrs.min_by do |p|
          # how many terminals will it take to reach reduce, if we try to
          # follow this rule?
          p.following.flat_map(&:shortest_production).size
        end

        automaton = self.dup
        path1 = automaton.follow_rule(ptr)
        next if automaton.error?

        path2 = automaton.path_to_success(traversed)
        # If that led to an infinite loop, `path2` will be `nil`.
        path2 && path1.concat(path2)
      end.compact.min_by(&:size)
    end

    def follow_shortest_rule_for(sym)
      rule = sym.heads.map(&:rule).min_by do |r|
        r.symbols.flat_map(&:shortest_production).size
      end
      follow_rule(rule.ptrs[0])
    end

    def follow_rule(ptr)
      actions = []
      initial_state = @state

      ptr.following.each do |sym|
        if sym.terminal?
          actions << sym
          consume!(sym)
        else
          actions.concat(follow_shortest_rule_for(sym))
        end
      end

      reduce_by!(ptr.rule)
      actions << ReduceStep.new(initial_state, @state, ptr.rule, ptr.target)
    end

    def dup
      result = super
      @sstack = @sstack.dup
      result
    end
  end
end