require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

module Racc
  class TestScanY < TestCase
    def setup
      file = File.join(ASSET_DIR, 'scan.y')
      parser = Racc::GrammarFileParser.new
      @result = parser.parse(File.read(file), File.basename(file))
      @states = @result.grammar.states
    end

    def assert_not_conflict(states)
      grammar = states.grammar

      assert_equal 0, states.sr_conflicts.size
      assert_equal 0, states.rr_conflicts.size
      assert_equal 0, grammar.useless_symbols.size
      assert_nil grammar.n_expected_srconflicts
    end

    def test_compile
      generator = Racc::ParserFileGenerator.new(@states, @result.params.dup)

      # it generates valid ruby
      assert Module.new {
        class_eval(generator.generate_parser)
      }

      assert_not_conflict(@states)
    end
  end
end
