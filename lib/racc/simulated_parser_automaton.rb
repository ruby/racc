require 'racc/state'
require 'set'

module Racc
  class SimulatedParserAutomaton
    def initialize(states)
      @states = states
      @state  = states.first
      @sstack = []
    end

    # consuming a terminal may set off a series of reduces before the terminal
    # is shifted
    def consume(token)
      action = @state.action[token] || @state.defact
      case action
      when Shift
        shifted(token)
        @sstack.push(@state)
        @state = action.goto_state
      when Reduce
        reduced(action.rule.target)
        action.rule.symbols.size.times { @state = @sstack.pop }
        @sstack.push(@state)
        @state = @state.gotos[action.rule.target].to_state
        consume(token)
      when Accept
        done
      when Error
        raise "Help!!! I don't know what to do!"
      else
        raise "Illegal action type: #{action.class}"
      end
    end

    # callbacks; can be overridden
    def shifted(token)
    end

    def reduced(nt)
    end

    def done
    end

    # TODO: also add a callback for error

    class TraversedStates < SimulatedParserAutomaton
      def initialize(states)
        super
        @traversed = Set[@state]
      end

      attr_reader :traversed

      def shifted(token)
        @traversed << @state
      end

      def reduced(nt)
        @traversed << @state
      end
    end
  end
end