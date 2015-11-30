require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))
require 'racc/simulated_parse_context'
require 'racc/dsl'

TestGrammar = Racc::DSL.define_grammar do
  g = self

  g.A = seq(:a, :B) | seq(:a, :C) | seq(:B, :C)
  g.B = seq(:a, :b) | seq(:b, :b, :b)
  g.C = seq(:c, :B) | seq(:c, :A)
end

LRecursiveGrammar = Racc::DSL.define_grammar do
  g = self

  g.A = seq(:a) | seq(:B, :a) | seq()
  g.B = seq(:b) | seq(:A, :b) | seq(:C, :b)
  g.C = seq(:c) | seq(:C, :c)
end

module Racc
  class TestSimulatedParseOnTestGrammar < TestCase
    def setup
      @context = Racc::SimulatedParseContext.new(TestGrammar)
    end

    def intern(sym)
      TestGrammar.intern(sym)
    end

    def test_initial_state
      active_ptrs = @context.reachable.map(&:ptr).sort_by(&:ident)
      assert_equal 1, active_ptrs.size
      assert_equal <<-END.chomp, @context.inspect
parse context:
$start : . A $end $end
      END
    end

    def test_shift_b
      @context.shift!(intern(:b))
      @context.shift!(intern(:b))
      assert_equal <<-END.chomp, @context.inspect
parse context:
$start : . A $end $end
  A : . B C
    B : b b . b
      END
    end

    def test_shift_a
      @context.shift!(intern(:a))
      assert_equal <<-END.chomp, @context.inspect
parse context:
$start : . A $end $end
  A : a . B
  A : a . C
  A : . B C
    B : a . b
      END
    end

    def test_reduce_B
      @context.shift!(intern(:a))
      @context.shift!(intern(:b))
      @context.reduce!(intern(:B))
      assert_equal <<-END.chomp, @context.inspect
parse context:
$start : . A $end $end
  A : B . C
      END
    end

    def test_reduce_B_without_shifting_first
      assert_raises do
        @context.reduce!(intern(:B))
      end
    end

    def test_lookahead_c
      @context.shift!(intern(:a))
      @context.lookahead!(intern(:c))
      assert_equal <<-END.chomp, @context.inspect
parse context:
$start : . A $end $end
  A : a . C
      END
    end

    def test_lookahead_after_reduce
      @context.shift!(intern(:a))
      @context.shift!(intern(:b))
      @context.lookahead!(intern(:b))
      assert_equal <<-END.chomp, @context.inspect
parse context:
$start : . A $end $end
  A : a . B
    B : b . b b
      END
    end

    def test_path_to_success_from_start
      assert_equal [intern(:A)], @context.path_to_success
    end

    def test_path_to_success_after_a
      @context.shift!(intern(:a))
      assert_equal [intern(:B), '(reduce to A)'], @context.path_to_success
    end

    def test_path_to_success_after_b
      @context.shift!(intern(:b))
      assert_equal [intern(:b), intern(:b), '(reduce to B)',
                    intern(:C), '(reduce to A)'],
                   @context.path_to_success
    end
  end

  class TestSimulatedParseOnLRecursiveGrammar < TestCase
    def setup
      @context = Racc::SimulatedParseContext.new(LRecursiveGrammar)
    end

    def intern(sym)
      LRecursiveGrammar.intern(sym)
    end

    def test_initial_state
      active_ptrs = @context.reachable.map(&:ptr).sort_by(&:ident)
      assert_equal 1, active_ptrs.size
      assert_equal <<-END.chomp, @context.inspect
parse context:
$start : . A $end $end
      END
    end

    def test_shift_a
      @context.shift!(intern(:a))
      assert_equal <<-END.chomp, @context.inspect
parse context:
$start : . A $end $end
  A : a .
  A : . B a
    B : . A b
      A : a .
      END
    end

    def test_shift_b
      @context.shift!(intern(:b))
      assert_equal <<-END.chomp, @context.inspect
parse context:
$start : . A $end $end
  A : . B a
    B : b .
    B : A b .
      END
    end

    def test_shift_c
      @context.shift!(intern(:c))
      assert_equal <<-END.chomp, @context.inspect
parse context:
$start : . A $end $end
  A : . B a
    B : . C b
      C : c .
      C : . C c
        C : c .
      END
    end

    def test_shift_a_consume_A
      @context.shift!(intern(:a))
      @context.consume!(intern(:A))
      assert_equal <<-END.chomp, @context.inspect
parse context:
$start : . A $end $end
  A : . B a
    B : . A b
      A : . B a
        B : A . b
    B : A . b
      END
    end

    def test_consume_C
      @context.consume!(intern(:C))
      assert_equal <<-END.chomp, @context.inspect
parse context:
$start : . A $end $end
  A : . B a
    B : . C b
      C : . C c
        C : C . c
      C : C . c
    B : C . b
      END
    end

    def test_reduce_A
      @context.reduce!(intern(:A))
      assert_equal <<-END.chomp, @context.inspect
parse context:
$start : . A $end $end
  A : . B a
    B : A . b
$start : A . $end $end
      END
    end
  end
end