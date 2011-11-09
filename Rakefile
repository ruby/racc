require 'rake'
require 'rubygems/package_task'
require 'rake/testtask'
require 'rake/clean'

include Rake::DSL

load './lib/racc/info.rb'

require 'tasks/file'
require 'tasks/gem'
require 'tasks/test'
require 'tasks/doc'
require 'tasks/email'

task :default => :test

task :test_pure do
  ENV["PURERUBY"] = "1"
  Rake.application[:test].invoke
end

task :clean => :clobber_docs
task :clean => :clobber_package

begin
  require 'rcov/rcovtask'
  Rcov::RcovTask.new do |t|
    t.test_files = FileList["test/test_*.rb"]
    t.verbose = true
    t.rcov_opts << "--no-color"
    t.rcov_opts << "--save coverage.info"
    t.rcov_opts << "-x ^/"
  end
  task "rcov" => :fuck_me
  task "rcov" => PTEXT

  task :fuck_me do
    ENV['PURERUBY'] = "1"
  end

  # this is for my emacs rcov overlay stuff on emacswiki.
  task :rcov_overlay do
    path = ENV["FILE"]
    rcov, eol = Marshal.load(File.read("coverage.info")).last[path], 1
    puts rcov[:lines].zip(rcov[:coverage]).map { |line, coverage|
      bol, eol = eol, eol + line.length
      [bol, eol, "#ffcccc"] unless coverage
    }.compact.inspect
  end
rescue LoadError
end

