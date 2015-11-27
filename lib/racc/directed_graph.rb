require 'racc/util'

module Racc
  class DirectedGraph < Array
    def initialize(size)
      super(size) { [] }
    end

    def add_child(from, to)
      self[from] << to
    end

    def remove_child(from, to)
      self[from].delete(to)
    end

    alias nodes each_index

    def children(node, &block)
      result = self[node]
      result.each(&block) if block_given?
      result
    end

    def reachable(start)
      Racc.set_closure([start]) do |node|
        self[node]
      end
    end

    def leaves(start)
      reachable(start).select { |node| self[node].empty? }
    end

    # shortest path between nodes; both start and end points are included
    def path(start, dest)
      # Dijkstra's algorithm
      return [start] if start == dest

      visited  = Set[start]
      worklist = children(start)
      paths    = {start => [start]}

      until visited.include?(dest)
        return nil if worklist.empty?
        node = worklist.min_by { |n| paths[n].size }
        node_path = paths[node]

        children(node) do |child|
          child_path = paths[child]
          if child_path.nil? || child_path.size > node_path.size + 1
            paths[child] = node_path.dup << child
          end
          worklist << child unless visited.include?(child)
        end

        visited << node
      end

      paths[dest]
    end

    # { node -> shortest path to it }
    def all_paths(start)
      # again, Dijkstra's algorithm
      paths = {start => [start]}

      Racc.set_closure([start]) do |node|
        node_path = paths[node]
        children(node) do |child|
          child_path = paths[child]
          if child_path.nil? || child_path.size > node_path.size + 1
            paths[child] = node_path.dup << child
          end
        end
      end

      paths
    end

    def dup
      super.map!(&:dup)
    end
  end

  class ReversibleDirectedGraph < DirectedGraph
    def initialize(size)
      super(size * 2)
      @offset = size
    end

    def add_child(from, to)
      self[from] << to
      self[@offset + to] << from
    end

    def remove_child(from, to)
      self[from].delete(to)
      self[@offset + to].delete(from)
    end

    def remove_node(node)
      self[node].each { |child| self[@offset + child].delete(node) }.clear
      self[@offset + node].each { |parent| self[parent].delete(node) }.clear
    end

    def nodes(&block)
      result = 0...@offset
      result.each(&block) if block_given?
      result
    end

    def parents(node, &block)
      result = self[@offset + node]
      result.each(&block) if block_given?
      result
    end

    # All nodes which can reach a node in `dests` (and `dests` themselves)
    def can_reach(dests)
      Racc.set_closure(dests) do |node|
        self[@offset + node]
      end
    end

    def reachable_from(nodes)
      Racc.set_closure(nodes) do |node|
        self[node]
      end
    end
  end
end
