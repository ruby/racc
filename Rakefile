require 'rake'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'rake/testtask'
require 'rake/clean'

load './lib/racc/info.rb'

require 'tasks/file'
require 'tasks/gem'
require 'tasks/test'
require 'tasks/doc'
require 'tasks/email'

task :default => :test

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
rescue LoadError
end

