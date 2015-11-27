require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

module Racc
  class TestChkY < TestCase
    def setup
      file = File.join(ASSET_DIR, 'chk.y')
      parser = Racc::GrammarFileParser.new
      @result = parser.parse(File.read(file), File.basename(file))
      @states = Racc::States.new(@result.grammar).compute_nfa.compute_dfa
    end

    def test_compile_chk_y
      generator = Racc::ParserFileGenerator.new(@states, @result.params)

      # it generates valid ruby
      assert Module.new {
        module_eval(generator.generate_parser)
      }

      grammar = @states.grammar

      assert_equal 0, @states.sr_conflicts.size
      assert_equal 0, @states.rr_conflicts.size
      assert_equal 0, grammar.useless_symbols.size
      assert_nil grammar.n_expected_srconflicts
    end
  end
end
