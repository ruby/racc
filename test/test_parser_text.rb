require File.expand_path(File.join(__dir__, 'case'))

module Racc
  class TestRaccParserText < TestCase
    def test_parser_text_require
      assert_not_match(/^require/, Racc::PARSER_TEXT)
      assert_in_out_err(%W[-I#{LIB_DIR} -rracc/parser-text -e$:.clear -eeval(Racc::PARSER_TEXT)])
    end
  end
end
