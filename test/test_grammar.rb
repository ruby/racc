require 'test/unit'
require 'racc/static'
require 'tempfile'

class TestGrammar < Test::Unit::TestCase
  private def with_parser(rule)
    parser = Racc::GrammarFileParser.new
    result = parser.parse(<<"eom", "foo.y")
class MyParser
rule
#{rule}
end
---- header
require 'strscan'
---- inner
def parse(str)
  @ss = StringScanner.new(str)
  do_parse
end
def next_token
  @ss.skip(/\\s+/)
  token = @ss.scan(/\\S+/) and [token, token]
end
eom
    states = Racc::States.new(result.grammar).nfa
    params = result.params.dup
    generator = Racc::ParserFileGenerator.new(states, params)
    Tempfile.create(%w[y .tab.rb]) do |f|
      generator.generate_parser_file(f.path)
      require f.path
      parser = MyParser.new
      yield parser
    end
    Object.__send__(:remove_const, :MyParser)
  end

  def test_optional
    with_parser("stmt: 'abc'?") do |parser|
      assert_equal "abc", parser.parse("abc")
      assert_equal nil, parser.parse("")
    end
  end

  def test_many
    with_parser("stmt: 'abc'*") do |parser|
      assert_equal [], parser.parse("")
      assert_equal ["abc"], parser.parse("abc")
      assert_equal ["abc", "abc"], parser.parse("abc abc")
      assert_equal ["abc", "abc", "abc"], parser.parse("abc abc abc")
    end
  end

  def test_many1
    with_parser("stmt: 'abc'+") do |parser|
      assert_raise(Racc::ParseError){ parser.parse("") }
      assert_equal ["abc"], parser.parse("abc")
      assert_equal ["abc", "abc"], parser.parse("abc abc")
      assert_equal ["abc", "abc", "abc"], parser.parse("abc abc abc")
    end
  end

  def test_group
    with_parser("stmt: ('a')") do |parser|
      assert_raise(Racc::ParseError){ parser.parse("") }
      assert_equal ["a"], parser.parse("a")
    end

    with_parser("stmt: ('a' 'b')") do |parser|
      assert_raise(Racc::ParseError){ parser.parse("") }
      assert_raise(Racc::ParseError){ parser.parse("a") }
      assert_equal ["a", "b"], parser.parse("a b")
    end
  end

  def test_group_or
    with_parser("stmt: ('a' | 'b')") do |parser|
      assert_raise(Racc::ParseError){ parser.parse("") }
      assert_equal ["a"], parser.parse("a")
      assert_equal ["b"], parser.parse("b")
    end
  end

  def test_group_many
    with_parser("stmt: ('a')*") do |parser|
      assert_equal [], parser.parse("")
      assert_equal [["a"]], parser.parse("a")
      assert_equal [["a"], ["a"]], parser.parse("a a")
    end

    with_parser("start: stmt\n stmt: ('a' 'b')*") do |parser|
      assert_equal [], parser.parse("")
      assert_equal [["a", "b"]], parser.parse("a b")
      assert_equal [["a", "b"], ["a", "b"]], parser.parse("a b a b")
    end
  end

  def test_group_or_many
    with_parser("stmt: ('a' | 'b')*") do |parser|
      assert_equal [], parser.parse("")
      assert_equal [["a"], ["a"]], parser.parse("a a")
      assert_equal [["a"], ["b"]], parser.parse("a b")
      assert_equal [["a"], ["b"], ["b"], ["a"]], parser.parse("a b b a")
    end
  end
end
