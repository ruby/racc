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

    def test_allow_double_colon_in_class_name
      parser = Racc::GrammarFileParser.new

      result = parser.parse(<<~RACC, 'namespace.y')
        class Foo::Bar
        rule
          target : TERM
        end
      RACC

      assert_equal 'Foo::Bar', result.params.classname
    end

    def test_reject_colon_prefixed_symbol_in_rule_body
      parser = Racc::GrammarFileParser.new
      error = assert_raise(CompileError) do
        parser.parse(<<~RACC, 'colon_prefixed_symbol.y')
          class Parse
          rule
            target : :TERM1
          end
        RACC
      end

      assert_equal "3: terminal and nonterminal symbols cannot start with ':', but got :TERM1", error.message
    end

    def test_reject_colon_prefixed_symbol_in_rule_alternative
      parser = Racc::GrammarFileParser.new
      error = assert_raise(CompileError) do
        parser.parse(<<~RACC, 'colon_prefixed_symbol.y')
          class Parse
          rule
            target : TERM1
                   | :TERM2
          end
        RACC
      end

      assert_equal "4: terminal and nonterminal symbols cannot start with ':', but got :TERM2", error.message
    end

    def test_reject_colon_prefixed_symbol_after_rhs_symbol
      parser = Racc::GrammarFileParser.new
      error = assert_raise(CompileError) do
        parser.parse(<<~RACC, 'colon_prefixed_symbol.y')
          class Parse
          rule
            target : TERM1
                   | term :TERM2
          end
        RACC
      end

      assert_equal "4: terminal and nonterminal symbols cannot start with ':', but got :TERM2", error.message
    end
  end
end
