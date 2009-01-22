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
