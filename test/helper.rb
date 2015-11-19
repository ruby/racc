$VERBOSE = true
require 'minitest/autorun'
require 'racc/static'
require 'fileutils'
require 'tempfile'
require 'timeout'

module Racc
  class TestCase < MiniTest::Unit::TestCase
    PROJECT_DIR = File.expand_path(File.join(File.dirname(__FILE__), '..'))

    TEST_DIR = File.join(PROJECT_DIR, 'test')

    RACC      = File.join(PROJECT_DIR, 'bin', 'racc')
    OUT_DIR   = File.join(TEST_DIR, 'out')
    TAB_DIR   = File.join(TEST_DIR, 'tab')
    LOG_DIR   = File.join(TEST_DIR, 'log')
    ERR_DIR   = File.join(TEST_DIR, 'err')
    ASSET_DIR = File.join(TEST_DIR, 'assets')

    INC = [
      File.join(PROJECT_DIR, 'lib'),
      File.join(PROJECT_DIR, 'ext'),
    ].join(':')

    def setup
      [OUT_DIR, TAB_DIR, LOG_DIR, ERR_DIR].each do |dir|
        FileUtils.mkdir_p(dir)
      end
    end

    def teardown
      [OUT_DIR, TAB_DIR, LOG_DIR, ERR_DIR].each do |dir|
        FileUtils.rm_rf(dir)
      end
    end

    def assert_compile asset, args = []
      asset = File.basename(asset, '.y')
      args = ([args].flatten) + [
        "#{ASSET_DIR}/#{asset}.y",
        '-Do',
        "-O#{OUT_DIR}/#{asset}",
        "-o#{TAB_DIR}/#{asset}",
      ]
      racc "#{args.join(' ')}"
    end

    def assert_debugfile asset, ok
      name = File.basename(asset, '.y')
      Dir.chdir(TEST_DIR) do
        File.foreach("log/#{name}.y") do |line|
          line.strip!
          case line
          when /sr/ then assert_equal "sr#{ok[0]}", line
          when /rr/ then assert_equal "rr#{ok[1]}", line
          when /un/ then assert_equal "un#{ok[2]}", line
          when /ur/ then assert_equal "ur#{ok[3]}", line
          when /ex/ then assert_equal "ex#{ok[4]}", line
          else
            raise TestFailed, 'racc outputs unknown debug report???'
          end
        end
      end
    end

    def assert_exec file
      file = File.basename(file, '.y')
      Dir.chdir(TEST_DIR) do
        ruby("tab/#{file}")
      end
    end

    def racc arg
      ruby "-S #{RACC} #{arg}"
    end

    def ruby arg
      Dir.chdir(TEST_DIR) do
        Tempfile.open 'test' do |io|
          cmd = "#{ENV['_'] || Gem.ruby} -I #{INC} #{arg} 2>#{io.path}"
          result = system(cmd)
          assert(result, io.read)
        end
      end
    end
  end
end
