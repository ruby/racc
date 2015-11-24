$VERBOSE = true
require 'minitest/autorun'
require 'racc/static'
require 'fileutils'
require 'tempfile'
require 'timeout'

module Racc
  class TestCase < Minitest::Test
    PROJECT_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..'))

    TEST_DIR = File.join(PROJECT_DIR, 'test')

    RACC      = File.join(PROJECT_DIR, 'bin', 'racc')
    OUT_DIR   = File.join(TEST_DIR, 'out')
    TAB_DIR   = File.join(TEST_DIR, 'tab') # generated parsers go here
    ASSET_DIR = File.join(TEST_DIR, 'assets') # test grammars
    REGRESS_DIR  = File.join(TEST_DIR, 'regress') # known-good generated outputs

    INC = [
      File.join(PROJECT_DIR, 'lib'),
      File.join(PROJECT_DIR, 'ext'),
    ].join(':')

    def setup
      [OUT_DIR, TAB_DIR].each do |dir|
        FileUtils.mkdir_p(dir)
      end
    end

    def teardown
      [OUT_DIR, TAB_DIR].each do |dir|
        FileUtils.rm_rf(dir)
      end
    end

    def assert_compile(asset, args = [])
      file = File.basename(asset, '.y')
      args = ([args].flatten) + [
        "#{ASSET_DIR}/#{file}.y",
        "-O#{OUT_DIR}/#{file}",
        "-o#{TAB_DIR}/#{file}",
      ]
      racc "#{args.join(' ')}"
    end

    def assert_warnings(dbg_output, expected)
      assert_equal expected[:useless_nts]   || 0, useless_nts(dbg_output)
      assert_equal expected[:useless_terms] || 0, useless_terms(dbg_output)
      assert_equal expected[:sr_conflicts]  || 0, sr_conflicts(dbg_output)
      assert_equal expected[:rr_conflicts]  || 0, rr_conflicts(dbg_output)
    end

    def assert_no_warnings(dbg_output)
      assert_warnings(dbg_output, {})
    end

    def assert_exec(asset)
      file = File.basename(asset, '.y')
      Dir.chdir(TEST_DIR) do
        ruby("#{TAB_DIR}/#{file}")
      end
    end

    def assert_output_unchanged(asset)
      file = File.basename(asset, '.y')

      expected = File.read("#{REGRESS_DIR}/#{file}")
      actual   = File.read("#{TAB_DIR}/#{file}")
      result   = (expected == actual)

      assert(result, "Output of test/assets/#{file}.y differed from " \
        "expectation. Try compiling it and diff with test/regress/#{file}.")
    end

    def racc(arg)
      ruby "#{RACC} #{arg}"
    end

    def ruby(arg)
      Dir.chdir(TEST_DIR) do
        Tempfile.open('test') do |io|
          executable = ENV['_'] || Gem.ruby
          if File.basename(executable) == 'bundle'
            executable = executable.dup << ' exec ruby'
          end

          result = system("#{executable} -I #{INC} #{arg} 2>#{io.path}")
          io.flush
          err = io.read
          assert(result, err)
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
  end
end
