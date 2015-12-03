$VERBOSE = true

require 'minitest/autorun'

require 'racc'
require 'racc/parser'
require 'racc/grammar_file_parser'
require 'racc/parser_file_generator'

require 'fileutils'
require 'tempfile'
require 'timeout'

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
      racc "#{args.join(' ')}", expect_success
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

    def assert_exec(asset)
      file = File.basename(asset, '.y')
      Dir.chdir(PROJECT_DIR) do
        ruby("#{TAB_DIR}/#{file}")
      end
    end

    def assert_parser_unchanged(asset)
      file = File.basename(asset, '.y')

      result = Dir.chdir(PROJECT_DIR) do
        File.read("#{REGRESS_DIR}/#{file}.rb") == File.read("#{TAB_DIR}/#{file}")
      end

      assert(result, "Output of test/assets/#{asset} differed from " \
        "expectation. Try compiling it and diff with test/regress/#{file}.rb:" \
        "\nruby -I./lib ./bin/racc -o tmp/#{file} test/assets/#{asset}; " \
        "colordiff tmp/#{file} test/regress/#{file}.rb")
    end

    def assert_output_unchanged(file, args, actual = nil)
      actual, args = args, nil if actual == nil
      result = Dir.chdir(PROJECT_DIR) do
        File.read("#{REGRESS_DIR}/#{file}") == actual
      end

      asset = File.basename(file, '.out') + '.y'
      assert(result, "Console output of test/assets/#{asset} differed from " \
        'expectation. Try compiling it and diff stderr with ' \
        "test/regress/#{file}:\nruby -I./lib ./bin/racc #{args} -o /dev/null " \
        "test/assets/#{asset} 2>tmp/#{file}; colordiff tmp/#{file} " \
        "test/regress/#{file}")
    end

    def racc(arg, expect_success = true)
      ruby "#{RACC} #{arg}", expect_success
    end

    def ruby(arg, expect_success = true)
      Dir.chdir(PROJECT_DIR) do
        Tempfile.open('test') do |io|
          executable = ENV['_'] || Gem.ruby
          if File.basename(executable) == 'bundle'
            executable = executable.dup << ' exec ruby'
          end

          result = system("#{executable} -I #{INC} #{arg} 2>#{io.path}")
          io.flush
          err = io.read
          assert(result, err) if expect_success
          return err
        end
      end
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
