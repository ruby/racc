require File.expand_path(File.join(__dir__, 'case'))

module Racc
  class TestRaccParserText < TestCase
    def test_parser_text_require
      assert_not_match(/^require/, Racc::PARSER_TEXT)
      ruby "-I#{LIB_DIR}", "-rracc/parser-text", "-e", "$:.clear", "-e", "eval(Racc::PARSER_TEXT)", quiet: true
    end

    def test_parser_text_require_with_backslash_loaded_feature
      ruby "-I#{LIB_DIR}", "-rracc/parser-text", "-e", <<~'RUBY', quiet: true
        require 'racc/info'
        $".map! do |feature|
          feature.end_with?('/racc/info.rb') ? 'C:\\tmp\\racc\\info.rb' : feature
        end
        eval(Racc::PARSER_TEXT)
      RUBY
    end
  end
end
