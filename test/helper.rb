$VERBOSE = true

require 'minitest/autorun'

require 'racc'
require 'racc/parser'
require 'racc/grammar_file_parser'
require 'racc/parser_file_generator'

require 'fileutils'
require 'tempfile'
require 'timeout'
require 'open3'

module Racc
  class TestCase < Minitest::Test
    PROJECT_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..'))
    RACC        = File.join(PROJECT_DIR, 'bin', 'racc')

    TAB_DIR     = File.join('test', 'tab')     # generated parsers go here
    ASSET_DIR   = File.join('test', 'assets')  # test grammars
    REGRESS_DIR = File.join('test', 'regress') # known-good generated outputs

    INC = [
      File.join(PROJECT_DIR, 'lib'),
      File.join(PROJECT_DIR, 'ext'),
    ].join(':')

    def setup
      FileUtils.mkdir_p(File.join(PROJECT_DIR, TAB_DIR))
    end

    def teardown
      FileUtils.rm_rf(File.join(PROJECT_DIR, TAB_DIR))
    end

    def assert_compile(asset, args = '', expect_success = true)
      file = File.basename(asset, '.y')
      args = [
        args,
        "#{ASSET_DIR}/#{file}.y",
        "-o#{TAB_DIR}/#{file}",
      ]
      racc "#{args.join(' ')}", file, expect_success
    end

    def assert_error(asset, args = '')
      assert_compile asset, args, false
    end

    def assert_warnings(dbg_output, expected)
      assert_equal expected[:useless_nts]   || 0, useless_nts(dbg_output)
      assert_equal expected[:useless_terms] || 0, useless_terms(dbg_output)
      assert_equal expected[:sr_conflicts]  || 0, sr_conflicts(dbg_output)
      assert_equal expected[:rr_conflicts]  || 0, rr_conflicts(dbg_output)
      assert_equal expected[:useless_prec]  || 0, useless_prec(dbg_output)
      assert_equal expected[:useless_rules] || 0, useless_rules(dbg_output)
    end

    def assert_no_warnings(dbg_output)
      assert_warnings(dbg_output, {})
    end

    def assert_exec(asset, embedded_runtime = false)
      file = File.basename(asset, '.y')
      Dir.chdir(PROJECT_DIR) do
        ruby("#{TAB_DIR}/#{file}", file, true, !embedded_runtime)
      end
    end

    def assert_parser_unchanged(asset)
      file = File.basename(asset, '.y')

      Dir.chdir(PROJECT_DIR) do
        assert_equal File.read("#{REGRESS_DIR}/#{file}.rb"), File.read("#{TAB_DIR}/#{file}")
      end
    end

    def assert_output_unchanged(file, args, actual = nil)
      actual, args = args, nil if actual == nil
      Dir.chdir(PROJECT_DIR) do
        assert_equal File.read("#{REGRESS_DIR}/#{file}"), actual
      end
    end

    def assert_html_unchanged(asset)
      assert_compile asset, '-S'

      file = File.basename(asset, '.y')
      Dir.chdir(PROJECT_DIR) do
        assert_equal File.read("#{REGRESS_DIR}/#{file}.html"), File.read("#{TAB_DIR}/#{file}")
      end
    end

    def racc(arg, file, expect_success = true)
      ruby "#{RACC} #{arg}", file, expect_success
    end

    def ruby(arg, file, expect_success = true, load_racc = true)
      err = ''
      result = nil
      Dir.chdir(PROJECT_DIR) do
        o, err, s = Open3.capture3 "#{ruby_executable} -Ilib #{arg}"
        result = s.success?
      end
      if expect_success
        assert(result, err)
        assert(File.exist?("./#{TAB_DIR}/#{file}"), "No file created!")
      end
      return err
    end

    def ruby_executable
      executable = ENV['_'] || Gem.ruby
      if File.basename(executable) == 'bundle'
        executable += ' exec ruby'
      end
      executable
    end

    def useless_nts(dbg_output)
      dbg_output.scan(/Useless nonterminal/).size
    end

    def useless_terms(dbg_output)
      dbg_output.scan(/Useless terminal/).size
    end

    def sr_conflicts(dbg_output)
      dbg_output.scan(/Shift\/reduce conflict/).size
    end

    def rr_conflicts(dbg_output)
      dbg_output.scan(/Reduce\/reduce conflict/).size
    end

    def useless_prec(dbg_output)
      dbg_output.scan(/The explicit precedence declaration on this rule/).size
    end

    def useless_rules(dbg_output)
      dbg_output.scan(/This rule will never be used due to low precedence/).size
    end
  end
end
