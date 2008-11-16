require 'rake'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'rake/testtask'

Rake::TestTask.new do |t|
  %w[ ext lib ].each do |dir|
    t.libs << dir
  end

  t.test_files = FileList['test/test_*.rb']
  t.verbose = true
end

task :default => :test
