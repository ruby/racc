require 'racc/util'

module Racc
  class DirectedGraph < Array
    def initialize(size)
      super(size) { [] }
    end

    def add_arrow(from, to)
      self[from] << to
    end

    def remove_arrow(from, to)
      self[from].delete(to)
    end

    alias nodes each_index

    def arrows(from, &block)
      self[from].each(&block)
    end

    def reachable(start)
      Racc.set_closure([start]) do |node|
        self[node]
      end
    end

    def leaves
      reachable.select { |node| self[node].empty? }
    end

    def invert
      inverted = DirectedGraph.new(size)
      each_with_index do |arrows, from|
        arrows.each { |to| inverted.add_arrow(to, from) }
      end
      inverted
    end
  end
end
