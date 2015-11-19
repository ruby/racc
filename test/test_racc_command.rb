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

    def test_rrconf_y
      assert_compile 'rrconf.y'
      assert_debugfile 'rrconf.y', [1,1,0,0]
    end

    def test_useless_y
      assert_compile 'useless.y'
      assert_debugfile 'useless.y', [0,0,1,2]
    end

    def test_opt_y
      assert_compile 'opt.y'
      assert_debugfile 'opt.y', []
      assert_exec 'opt.y'
    end

    def test_yyerr_y
      assert_compile 'yyerr.y'
      assert_debugfile 'yyerr.y', []
      assert_exec 'yyerr.y'
    end

    def test_recv_y
      assert_compile 'recv.y'
      assert_debugfile 'recv.y', [5,10,1,4]
    end

    def test_ichk_y
      assert_compile 'ichk.y'
      assert_debugfile 'ichk.y', []
      assert_exec 'ichk.y'
    end

    def test_intp_y
      assert_compile 'intp.y'
      assert_debugfile 'intp.y', []
      assert_exec 'intp.y'
    end

    def test_expect_y
      assert_compile 'expect.y'
      assert_debugfile 'expect.y', [1,0,0,0,1]
    end

    def test_nullbug1_y
      assert_compile 'nullbug1.y'
      assert_debugfile 'nullbug1.y', [0,0,0,0]
    end

    def test_nullbug2_y
      assert_compile 'nullbug2.y'
      assert_debugfile 'nullbug2.y', [0,0,0,0]
    end

    def test_firstline_y
      assert_compile 'firstline.y'
      assert_debugfile 'firstline.y', []
    end

    def test_nonass_y
      assert_compile 'nonass.y'
      assert_debugfile 'nonass.y', []
      assert_exec 'nonass.y'
    end

    def test_digraph_y
      assert_compile 'digraph.y'
      assert_debugfile 'digraph.y', []
      assert_exec 'digraph.y'
    end

    def test_noend_y
      assert_compile 'noend.y'
      assert_debugfile 'noend.y', []
    end

    def test_norule_y
      assert_raises(MiniTest::Assertion) {
        assert_compile 'norule.y'
      }
    end

    def test_unterm_y
      assert_raises(MiniTest::Assertion) {
        assert_compile 'unterm.y'
      }
    end

    # Regression test for a problem where error recovery at EOF would cause
    # a Racc-generated parser to go into an infinite loop (on some grammars)
    def test_error_recovery_y
      assert_compile 'error_recovery.y'
      Timeout.timeout(10) do
        assert_exec 'error_recovery.y'
      end
    end
  end
end
