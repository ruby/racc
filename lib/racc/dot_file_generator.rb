require 'racc/color'

module Racc
  class DotFileGenerator
    def initialize(states, relevant=states)
      @states   = states
      @relevant = relevant # can show only a subset of states
    end

    def generate_dot
      prelude << node_labels << arrows << conclusion
    end

    def generate_dot_file(destpath)
      if destpath == '-'
        $stdout.puts generate_dot
      else
        File.open(destpath, 'w') do |f|
          f.write generate_dot
        end
      end
    end

    private

    # Sections of DOT output

    def prelude
      "digraph {\n"
    end

    def node_labels
      @relevant.sort_by(&:ident).map do |state|
        core = Color.without_color { state.core.map(&:to_s).join("\n") }
        %{#{name(state)} [label=#{core.inspect}]\n}
      end.join
    end

    def arrows
      @relevant.sort_by(&:ident).map do |state|
        state.gotos.group_by { |t, goto| goto.to_state }.select do |s, ts|
          @relevant.include?(s)
        end.map do |s, ts|
          %{#{name(state)} -> #{name(s)} [label=#{tokens(ts.map(&:first))}]\n}
        end.join
      end.join
    end

    def conclusion
      "}"
    end

    # Helpers

    def name(state)
      "state#{state.ident}"
    end

    def tokens(syms)
      Color.without_color { syms.map(&:to_s).join(', ') }.inspect
    end
  end
end
