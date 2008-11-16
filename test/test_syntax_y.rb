require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

module Racc
  class TestSyntaxY < TestCase
    def test_compile_script
      assert_compile 'syntax', '-v'
      assert_debugfile 'syntax', [0,0,0,0,0]
    end
  end
end
