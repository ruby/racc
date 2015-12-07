require 'racc/util'
require 'racc/color'
require 'tempfile'
require 'set'

module Racc
  module Graph
    # Algorithms which work on any of the graph implementations below
    module Algorithms
      # shortest path between nodes; both start and end points are included
      def shortest_path(start, dest)
        # Dijkstra's algorithm
        return [start] if start == dest

        visited  = Set[start]
        worklist = [start]
        paths    = {start => [start]}

        until visited.include?(dest)
          return nil if worklist.empty?
          node = worklist.shift
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

      # { node -> shortest path to it from start node }
      # if a block is provided, it is a 'cost function'
      # all paths include both start and end points
      def shortest_paths
        # again, Dijkstra's algorithm
        paths = {@start => [0, @start]} # cache total path cost

        Racc.set_closure([@start]) do |node|
          node_path = paths[node]
          children(node) do |child|
            child_path = paths[child]
            cost = block_given? ? yield(node, child) : 1
            if child_path.nil? || child_path[0] > node_path[0] + cost
              paths[child] = node_path.dup.tap { |p| p[0] += cost } << child
            end
          end
        end

        paths.each_value { |p| p.shift } # drop cached total costs
        paths
      end

      # only paths with no loops will be found
      # start and end points are included
      # this can be very slow on graphs with a lot of transitions!
      def all_paths(src, dest, current=src, traversed=[src], result=[])
        children(current) do |child|
          if child == dest
            result << (traversed.dup << child)
          elsif !traversed.include?(child)
            traversed.push(child)
            all_paths(src, dest, child, traversed, result)
            traversed.pop
          end
        end
        result
      end

      def to_gif(options={})
        filename = options[:filename] || "graph.gif"
        filename <<= ".gif" unless filename.end_with?(".gif")
        Tempfile.open("graph") do |f|
          f.write(self.to_dot(options))
          f.flush
          `dot -Tgif #{f.path} -o "#{filename}"`
        end
      end

      def to_dot(options={})
        s = "digraph {\n"
        s <<= "graph [label=\"#{options[:title]}\"]\n" if options[:title]
        (options[:highlight] || []).each do |node|
          s <<= "\"#{node.hash}\" [style=filled fillcolor=gold]\n"
        end
        s <<= nodes.map do |node|
          %{"#{node.hash}" [label="#{node_caption(node)}"]} <<
          children(node).map { |child| %{"#{node.hash}" -> "#{child.hash}"} }.join("\n")
        end.join("\n")
        s << "}"
      end
    end

    # An implementation which is fast when the exact number of nodes is known
    # in advance, and each one can be identified by an integer
    class Finite < Array
      include Algorithms

      def initialize(size)
        super(size) { Set.new }
        @start = nil
      end

      def start=(idx)
        @start = idx
      end

      def add_child(from, to)
        self[from] << to
        to
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

      def reachable
        reachable_from([@start])
      end

      def reachable_from(nodes)
        Racc.set_closure(nodes) { |node| self[node] }
      end

      def leaves
        reachable.select { |node| self[node].empty? }
      end

      def dup
        super.map!(&:dup)
      end

      def freeze
        each(&:freeze)
      end
    end

    # Like Graph::Finite, but with backpointers from children to parents as well
    class Reversible < Finite
      def initialize(size)
        super(size * 2)
        @offset = size
      end

      def add_child(from, to)
        self[from] << to
        self[@offset + to] << from
        to
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
        Racc.set_closure(dests) { |node| self[@offset + node] }
      end
    end

    # Each vector has a label; labels are unique for any source node
    # There can be multiple vectors from one node to another, as long as
    # each vector has a different label
    class Labeled < Array
      include Algorithms

      def initialize(size)
        super(size) { {} }
        concat(map { Set.new }) # backpointers
        @start  = nil
        @offset = size
      end

      attr_reader :start

      def start=(idx)
        @start = idx
      end

      def add_vector(from, to, label)
        if self[from].key?(label)
          raise "Vector #{label.inspect} from node #{from} already exists"
        end
        self[from][label] = to
        self[to + @offset] << from
        to
      end

      def remove_vector(from, to, label)
        self[from].delete(label)
        self[to + @offset].delete(from)
      end

      def nodes(&block)
        result = 0...@offset
        result.each(&block) if block_given?
        result
      end

      def children(node, &block)
        result = self[node].values
        result.each(&block) if block_given?
        result
      end

      def vectors(node, &block)
        result = self[node]
        result.each(&block) if block_given?
        result
      end

      def parents(node, &block)
        result = self[@offset + node]
        result.each(&block) if block_given?
        result
      end

      def reachable
        reachable_from([@start])
      end

      def reachable_from(nodes)
        Racc.set_closure(nodes) { |node| self[node].values }
      end

      def leaves
        reachable.select { |node| self[node].empty? }
      end

      # like #all_paths, but return sequences of vector labels, not sequences
      # of nodes
      def all_vector_paths(src, dest, current=src, kill=0, path=[], result=[])
        vectors(current) do |label, child|
          if child == dest
            result << (path.dup << label)
          elsif kill[child] == 0
            path.push(label)
            all_vector_paths(src, dest, child, kill | (1 << child), path, result)
            path.pop
          end
        end
        result
      end

      # like #shortest_paths, but return sequences of vector labels
      def shortest_vector_paths
        paths = {@start => [0]} # cache total path cost

        Racc.set_closure([@start]) do |node|
          node_path = paths[node]
          vectors(node) do |label, child|
            child_path = paths[child]
            cost = block_given? ? yield(label) : 1
            if child_path.nil? || child_path[0] > node_path[0] + cost
              paths[child] = node_path.dup.tap { |p| p[0] += cost } << label
            end
          end
          children(node)
        end

        paths.each_value { |p| p.shift } # drop cached total costs
        paths
      end

      def dup
        super.map!(&:dup)
      end

      def freeze
        each(&:freeze)
      end
    end

    # This implementation uses an object for each node, rather than identifying
    # nodes by integers
    # this means we can add as many nodes as we want
    # Graph::Node can also be subclassed and have extra methods added
    class Generic
      include Algorithms

      def initialize
        @nodes = Set.new
        @start = nil
      end

      attr_reader :nodes, :start

      def start=(node)
        @nodes << node
        @start = node
      end

      def remove_node(node)
        @start = nil if node == @start
        @nodes.delete(node)
        node.out.each { |other| other.in.delete?(node) }
        node.in.each  { |other| other.out.delete?(node) }
      end

      def add_child(from, to)
        @nodes   << to
        from.out << to
        to.in    << from
        to
      end

      def remove_child(from, to)
        from.out.delete(to)
        to.in.delete(from)
      end

      def children(node, &block)
        node.out.each(&block) if block_given?
        node.out
      end

      def reachable
        reachable_from([@start])
      end

      def reachable_from(nodes)
        Racc.set_closure(nodes) { |node| node.out }
      end

      def can_reach(dests)
        Racc.set_closure(dests) { |node| node.in }
      end

      def leaves
        @nodes.select { |node| node.out.empty? }
      end

      def node_caption(node)
        Color.without_color { node.ptr.to_s }
      end

      def freeze
        super
        @nodes.each(&:freeze)
      end
    end

    class Node
      def initialize
        @out, @in = Set.new, Set.new
      end

      attr_reader :out, :in
    end
  end
end
