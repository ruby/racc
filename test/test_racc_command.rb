require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

module Racc
  class TestRaccCommand < TestCase
    def test_syntax_y
      assert_compile 'syntax.y', '-v'
      assert_debugfile 'syntax.y', [0,0,0,0,0]
    end

    def test_percent_y
      assert_compile 'percent.y'
      assert_debugfile 'percent.y', []
      assert_exec 'percent.y'
    end

    def test_scan_y
      assert_compile 'scan.y'
      assert_debugfile 'scan.y', []
      assert_exec 'scan.y'
    end

    def test_newsyn_y
      assert_compile 'newsyn.y'
      assert_debugfile 'newsyn.y', []
    end
  end
end
