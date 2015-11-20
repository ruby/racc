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
      generator = Racc::ParserFileGenerator.new(@states, @result.params.dup)

      # it generates valid ruby
      assert Module.new {
        self.instance_eval(generator.generate_parser, __FILE__, __LINE__)
      }

      grammar = @states.grammar

      assert_equal 0, @states.sr_conflicts.size
      assert_equal 0, @states.rr_conflicts.size
      assert_equal 0, grammar.useless_nonterminals.size
      assert_nil grammar.n_expected_srconflicts
    end

    def test_compile_chk_y_line_convert
      params = @result.params.dup
      params.convert_line_all = true

      generator = Racc::ParserFileGenerator.new(@states, @result.params.dup)

      # it generates valid ruby
      assert Module.new {
        self.instance_eval(generator.generate_parser, __FILE__, __LINE__)
      }

      grammar = @states.grammar

      assert_equal 0, @states.sr_conflicts.size
      assert_equal 0, @states.rr_conflicts.size
      assert_equal 0, grammar.useless_nonterminals.size
      assert_nil grammar.n_expected_srconflicts
    end
  end
end
