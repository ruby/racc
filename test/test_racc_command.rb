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

    def test_normal_y
      assert_compile 'normal.y'
      assert_debugfile 'normal.y', []

      assert_compile 'normal.y', '-vg'
      assert_debugfile 'normal.y', []
    end

    def test_chk_y
      assert_compile 'chk.y', '-vg'
      assert_debugfile 'chk.y', []
      assert_exec 'chk.y'

      assert_compile 'chk.y', '--line-convert-all'
      assert_debugfile 'chk.y', []
      assert_exec 'chk.y'
    end

    def test_echk_y
      assert_compile 'echk.y', '-E'
      assert_debugfile 'echk.y', []
      assert_exec 'echk.y'
    end

    def test_err_y
      assert_compile 'err.y'
      assert_debugfile 'err.y', []
      assert_exec 'err.y'
    end

    def test_mailp_y
      assert_compile 'mailp.y'
      assert_debugfile 'mailp.y', []
    end

    def test_conf_y
      assert_compile 'conf.y', '-v'
      assert_debugfile 'conf.y', [4,1,1,2]
    end
  end
end
