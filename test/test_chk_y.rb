require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

module Racc
  class TestChkY < TestCase
    def setup
      file = File.join(ASSET_DIR, 'chk.y')
      parser = Racc::GrammarFileParser.new
      @result = parser.parse(File.read(file), File.basename(file))
      @states = @result.grammar.states
    end

    def test_compile_chk_y
      generator = Racc::ParserFileGenerator.new(@states, @result.params)

      # it generates valid ruby
      assert Module.new {
        module_eval(generator.generate_parser)
      }

      assert_not_conflict(@states)
    end
  end
end
