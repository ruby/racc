require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))
require 'racc/directed_graph'

module Racc
  module GraphTests
    def setup
      init
      @graph.start = @a
      @graph.add_child(@a, @b)
      @graph.add_child(@a, @c)
      @graph.add_child(@c, @d)
    end

    def test_reachable
      assert_equal 4, @graph.reachable.size
      @graph.remove_child(@c, @d)
      assert_equal 3, @graph.reachable.size
      assert !@graph.reachable.include?(@d)

      return unless @graph.respond_to? :remove_node
      @graph.remove_node(@b)
      assert_equal 2, @graph.reachable.size
    end

    def test_shortest_path
      assert_equal [@a, @c, @d], @graph.shortest_path(@a, @d)
      assert_equal [@a, @b],     @graph.shortest_path(@a, @b)
      assert_equal [@a],         @graph.shortest_path(@a, @a)
    end

    def test_shortest_paths
      paths = @graph.shortest_paths
      assert_equal [@a, @c, @d], paths[@d]
      assert_equal [@a, @b],     paths[@b]
      assert_equal [@a],         paths[@a]
    end

    def test_all_paths
      @graph.add_child(@b, @d)
      @graph.add_child(@a, @d)
      paths = @graph.all_paths(@a, @d)
      assert_equal Set[[@a, @d], [@a, @b, @d], [@a, @c, @d]], Set.new(paths)
    end

    def test_leaves
      assert_equal [@b, @d], @graph.leaves.to_a
    end
  end

  class TestGenericDirectedGraph < TestCase
    include GraphTests

    def init
      @graph = Racc::Graph::Generic.new
      @a, @b, @c, @d = 4.times.map { Racc::Graph::Node.new }
    end
  end

  class TestFiniteGraph < TestCase
    include GraphTests

    def init
      @graph = Racc::Graph::Finite.new(4)
      @a, @b, @c, @d = 0, 1, 2, 3
    end
  end

  class TestReversibleFiniteGraph < TestCase
    include GraphTests

    def init
      @graph = Racc::Graph::Reversible.new(4)
      @a, @b, @c, @d = 0, 1, 2, 3
    end
  end
end