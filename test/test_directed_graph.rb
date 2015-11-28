require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))
require 'racc/directed_graph'

module Racc
  class TestGenericDirectedGraph < TestCase
    def setup
      @graph = Racc::Graph::Generic.new
      @a, @b, @c, @d = 4.times.map { Racc::Graph::Node.new }
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
      @graph.remove_node(@b)
      assert_equal 2, @graph.reachable.size
    end

    def test_all_paths
      paths = @graph.all_paths
      assert_equal [@a, @c, @d], paths[@d]
      assert_equal [@a, @b], paths[@b]
      assert_equal [@a], paths[@a]
    end

    def test_leaves
      assert_equal [@b, @d], @graph.leaves.to_a
    end
  end
end