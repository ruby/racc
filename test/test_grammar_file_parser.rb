require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

module Racc
  class TestGrammarFileParser < TestCase
    def test_parse
      file = File.join(ASSET_DIR, 'yyerr.y')
      parser = Racc::GrammarFileParser.new
      parser.parse(File.read(file), File.basename(file))
    end
  end
end
