require File.expand_path(File.join(__dir__, 'case'))

module Racc
  class TestGrammarFileParser < TestCase
    def test_parse
      file = File.join(ASSET_DIR, 'yyerr.y')

      debug_flags = Racc::DebugFlags.parse_option_string('o')
      assert debug_flags.status_logging

      parser = Racc::GrammarFileParser.new(debug_flags)
      parser.parse(File.read(file), File.basename(file))
    end

    def test_no_result_var_with_many_operator
      grammar_source = <<~GRAMMAR
        class TestParser
        options no_result_var

        rule
          root
            : 'a' 'b'*
      GRAMMAR

      debug_flags = Racc::DebugFlags.parse_option_string('')
      parser = Racc::GrammarFileParser.new(debug_flags)
      result = parser.parse(grammar_source, 'test.y')

      assert_equal false, result.params.result_var?

      actions = result.grammar.each_rule.map { |rule| rule.action.source&.text }.compact
      actions.each do |action|
        refute_match(/\Aresult\s*=/, action, "Action should not start with 'result =' when no_result_var is set")
      end
    end

    def test_no_result_var_with_many1_operator
      grammar_source = <<~GRAMMAR
        class TestParser
        options no_result_var

        rule
          root
            : 'a' 'b'+
      GRAMMAR

      debug_flags = Racc::DebugFlags.parse_option_string('')
      parser = Racc::GrammarFileParser.new(debug_flags)
      result = parser.parse(grammar_source, 'test.y')

      assert_equal false, result.params.result_var?

      actions = result.grammar.each_rule.map { |rule| rule.action.source&.text }.compact
      actions.each do |action|
        refute_match(/\Aresult\s*=/, action, "Action should not start with 'result =' when no_result_var is set")
      end
    end

    def test_no_result_var_with_group_operator
      grammar_source = <<~GRAMMAR
        class TestParser
        options no_result_var

        rule
          root
            : ('a' | 'b')
      GRAMMAR

      debug_flags = Racc::DebugFlags.parse_option_string('')
      parser = Racc::GrammarFileParser.new(debug_flags)
      result = parser.parse(grammar_source, 'test.y')

      assert_equal false, result.params.result_var?

      actions = result.grammar.each_rule.map { |rule| rule.action.source&.text }.compact
      actions.each do |action|
        refute_match(/\Aresult\s*=/, action, "Action should not start with 'result =' when no_result_var is set")
      end
    end

    def test_result_var_with_many_operator
      grammar_source = <<~GRAMMAR
        class TestParser

        rule
          root
            : 'a' 'b'*
      GRAMMAR

      debug_flags = Racc::DebugFlags.parse_option_string('')
      parser = Racc::GrammarFileParser.new(debug_flags)
      result = parser.parse(grammar_source, 'test.y')

      assert_equal true, result.params.result_var?

      actions = result.grammar.each_rule.map { |rule| rule.action.source&.text }.compact.reject(&:empty?)
      assert actions.any? { |action| action.match?(/\Aresult\s*=/) }, "Action should start with 'result =' when result_var is enabled"
    end

    def test_no_result_var_no_warnings
      grammar_file = Tempfile.new(['test_no_result_var', '.y'])
      grammar_file.write(<<~GRAMMAR)
        class TestParser
        options no_result_var

        rule
          root
            : 'a' 'b'*
            | 'c' 'd'+
            | ('e' | 'f')
      GRAMMAR
      grammar_file.close

      output_file = Tempfile.new(['test_no_result_var', '.rb'])
      output_file.close

      system("ruby", "-I#{LIB_DIR}", "-S", RACC, "-o", output_file.path, grammar_file.path)
      assert $?.success?, "racc command failed"

      warnings = `ruby -W #{output_file.path} 2>&1`
      assert_equal "", warnings, "Expected no warnings but got: #{warnings}"
    ensure
      grammar_file&.unlink
      output_file&.unlink
    end
  end
end
