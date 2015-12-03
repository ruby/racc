require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

module Racc
  class TestRaccCommand < TestCase
    def test_syntax_y
      err = assert_compile 'syntax.y', '-v'
      assert_no_warnings err
    end

    def test_percent_y
      err = assert_compile 'percent.y'
      assert_no_warnings err
      assert_exec 'percent.y'
    end

    def test_scan_y
      err = assert_compile 'scan.y'
      assert_no_warnings err
      assert_exec 'scan.y'
    end

    def test_newsyn_y
      err = assert_compile 'newsyn.y'
      assert_no_warnings err
    end

    def test_normal_y
      err = assert_compile 'normal.y', '--color'
      assert_warnings err, useless_prec: 1
      assert_output_unchanged 'normal.out', '--color', err

      err = assert_compile 'normal.y', '-vt'
      assert_warnings err, useless_prec: 1
    end

    def test_chk_y
      err = assert_compile 'chk.y', '-vt'
      assert_no_warnings err
      assert_exec 'chk.y'
    end

    def test_echk_y
      err = assert_compile 'echk.y', '-E'
      assert_no_warnings err
      assert_exec 'echk.y'
    end

    def test_err_y
      err = assert_compile 'err.y'
      assert_no_warnings err
      assert_exec 'err.y'
    end

    def test_mailp_y
      err = assert_compile 'mailp.y'
      assert_no_warnings err
    end

    def test_conf_y
      err = assert_compile 'conf.y', '-v'
      assert_warnings err, sr_conflicts: 4, useless_nts: 1
    end

    def test_rrconf_y
      err = assert_compile 'rrconf.y'
      assert_warnings err, sr_conflicts: 1, rr_conflicts: 1
    end

    def test_useless_y
      err = assert_compile 'useless.y'
      assert_warnings err, useless_nts: 2
    end

    def test_duplicate_y
      err = assert_error 'duplicate.y'
      assert_output_unchanged 'duplicate.out', err
    end

    def test_badprec1_y
      err = assert_error 'badprec1.y', '--color'
      assert_output_unchanged 'badprec1.out', '--color', err
    end

    def test_badprec2_y
      err = assert_error 'badprec2.y', '--color'
      assert_output_unchanged 'badprec2.out', '--color', err
    end

    def test_badsyntax_y
      err = assert_error 'badsyntax.y', '--color'
      assert_output_unchanged 'badsyntax.out', '--color', err
    end

    def test_badrule1_y
      err = assert_error 'badrule1.y', '--color'
      assert_output_unchanged 'badrule1.out', '--color', err
    end

    def test_badrule2_y
      err = assert_error 'badrule2.y', '--color'
      assert_output_unchanged 'badrule2.out', '--color', err
    end

    def test_not_lalr
      # grammars which are LR(1), but not LALR(1)
      err = assert_compile 'lr_not_lalr.y', '--color -v'
      assert_output_unchanged 'lr_not_lalr.out', '--color -v', err
      err = assert_compile 'lr_not_lalr2.y', '--color -v'
      assert_output_unchanged 'lr_not_lalr2.out', '--color -v', err
    end

    def test_opt_y
      err = assert_compile 'opt.y'
      assert_no_warnings err
      assert_exec 'opt.y'
    end

    def test_yyerr_y
      err = assert_compile 'yyerr.y'
      assert_no_warnings err
      assert_exec 'yyerr.y'
    end

    def test_recv_y
      err = assert_compile 'recv.y'
      assert_warnings err, sr_conflicts: 5, useless_rules: 3, rr_conflicts: 10, useless_nts: 1
    end

    def test_ichk_y
      err = assert_compile 'ichk.y'
      assert_no_warnings err
      assert_exec 'ichk.y'
    end

    def test_intp_y
      err = assert_compile 'intp.y'
      assert_no_warnings err
      assert_exec 'intp.y'
    end

    def test_expect_y
      err = assert_compile 'expect.y'
      # expect has 1 S/R conflict, but it is expected
      assert_no_warnings err
    end

    def test_nullbug1_y
      err = assert_compile 'nullbug1.y'
      assert_no_warnings err
    end

    def test_nullbug2_y
      err = assert_compile 'nullbug2.y'
      assert_no_warnings err
    end

    def test_firstline_y
      err = assert_compile 'firstline.y'
      assert_no_warnings err
    end

    def test_nonass_y
      err = assert_compile 'nonass.y'
      assert_no_warnings err
      assert_exec 'nonass.y'
    end

    def test_digraph_y
      err = assert_compile 'digraph.y'
      assert_no_warnings err
      assert_exec 'digraph.y'
    end

    def test_noend_y
      err = assert_compile 'noend.y'
      assert_no_warnings err
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

    # Regression tests based on real-world gramamrs from various gems
    # For each test, we check whether the generated parser file is byte-for-byte
    # identical to the known-good file in test/regress

    # .y files from parser gem

    def test_ruby18
      err = assert_compile 'ruby18.y'
      assert_warnings err, useless_terms: 1
      assert_parser_unchanged 'ruby18.y'
    end

    def test_ruby22
      err = assert_compile 'ruby22.y'
      assert_warnings err, useless_terms: 1
      assert_parser_unchanged 'ruby22.y'
    end

    # .y file from csspool gem

    def test_csspool
      err = assert_compile 'csspool.y', '--color -v'
      assert_warnings err, sr_conflicts: 5, rr_conflicts: 3
      assert_parser_unchanged 'csspool.y'
      assert_output_unchanged 'csspool.out', '--color -v', err
    end

    # .y file from opal gem

    def test_opal
      err = assert_compile 'opal.y', '--color -v'
      assert_warnings err, useless_terms: 3, useless_prec: 2
      assert_parser_unchanged 'opal.y'
      assert_output_unchanged 'opal.out', '--color -v', err
    end

    # .y file from journey gem

    def test_journey
      err = assert_compile 'journey.y'
      assert_no_warnings err
      assert_parser_unchanged 'journey.y'
    end

    # .y file from nokogiri gem

    def test_nokogiri_css
      err = assert_compile 'nokogiri-css.y'
      assert_warnings err, useless_terms: 1, rr_conflicts: 1
      assert_parser_unchanged 'nokogiri-css.y'
    end

    # .y file from bibtex-ruby gem

    def test_bibtex
      err = assert_compile 'bibtex.y'
      assert_no_warnings err
      assert_parser_unchanged 'bibtex.y'
    end

    # .y file from edtf-ruby gem

    def test_edtf
      err = assert_compile 'edtf.y', '-v'
      assert_warnings err, useless_terms: 2
      assert_parser_unchanged 'edtf.y'
      assert_output_unchanged 'edtf.out', '-v', err
    end

    # .y file from namae gem

    def test_namae
      err = assert_compile 'namae.y'
      assert_no_warnings err
      assert_parser_unchanged 'namae.y'
    end

    # .y file from liquor gem

    def test_liquor
      err = assert_compile 'liquor.y'
      # liquor has S/R conflicts, but they are expected
      assert_warnings err, useless_terms: 1
      assert_parser_unchanged 'liquor.y'
    end

    # .y file from nasl gem

    def test_nasl
      err = assert_compile 'nasl.y'
      # nasl has 1 S/R conflict, but it is expected
      assert_no_warnings err
      assert_parser_unchanged 'nasl.y'
    end

    # .y file from riml gem

    def test_riml
      err = assert_compile 'riml.y'
      assert_warnings err, useless_terms: 1, sr_conflicts: 289
      assert_parser_unchanged 'riml.y'
    end

    # .y file from ruby-php-serialization gem

    def test_php_serialization
      err = assert_compile 'php_serialization.y'
      assert_no_warnings err
      assert_parser_unchanged 'php_serialization.y'
    end

    # .y file from huia language implementation

    def test_huia
      err = assert_compile 'huia.y'
      assert_warnings err, sr_conflicts: 285
      assert_parser_unchanged 'huia.y'
    end

    # .y files from rdtool gem

    def test_rdtool
      err1 = assert_compile 'rdblockparser.y'
      err2 = assert_compile 'rdinlineparser.y'
      assert_no_warnings err1
      assert_no_warnings err2
      assert_parser_unchanged 'rdblockparser.y'
      assert_parser_unchanged 'rdinlineparser.y'
    end

    # .y file from cast gem

    def test_cast
      err = assert_compile 'cast.y'
      # cast has 1 S/R conflict, but it is expected
      assert_no_warnings err
      assert_parser_unchanged 'cast.y'
    end

    # .y file from cadenza gem

    def test_cadenza
      err = assert_compile 'cadenza.y'
      # cadenza has 37 S/R conflicts, but they are expected
      assert_no_warnings err
      assert_parser_unchanged 'cadenza.y'
    end

    # .y file from mediacloth gem

    def test_mediacloth
      err = assert_compile 'mediacloth.y'
      assert_no_warnings err
      assert_parser_unchanged 'mediacloth.y'
    end

    # .y file from twowaysql gem

    def test_twowaysql
      err = assert_compile 'twowaysql.y'
      assert_warnings err, sr_conflicts: 4
      assert_parser_unchanged 'twowaysql.y'
    end

    # .y file from machete gem

    def test_machete
      err = assert_compile 'machete.y'
      assert_no_warnings err
      assert_parser_unchanged 'machete.y'
    end

    # .y file from mof gem

    def test_mof
      err = assert_compile 'mof.y', '-v --color'
      assert_warnings err, useless_terms: 4, useless_rules: 1, sr_conflicts: 7, rr_conflicts: 4
      assert_parser_unchanged 'mof.y'
      assert_output_unchanged 'mof.out', '-v --color', err
    end

    # .y file from tp_plus gem

    def test_tp_plus
      err = assert_compile 'tp_plus.y'
      assert_warnings err, useless_terms: 2, sr_conflicts: 21
      assert_parser_unchanged 'tp_plus.y'
    end

    # .y file from eye_of_newt gem

    def test_eye_of_newt
      err = assert_compile 'eye-of-newt.y'
      assert_warnings err, sr_conflicts: 7, rr_conflicts: 5
      assert_parser_unchanged 'eye-of-newt.y'
    end
  end
end
