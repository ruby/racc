require 'rake'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'rake/testtask'
require 'rake/clean'

kind = Config::CONFIG['DLEXT']

EXT = "ext/racc/cparse/cparse.#{kind}"

[
  EXT,
  'lib/racc/parser-text.rb'
].each { |f| CLEAN << f }

file 'lib/racc/parser.rb'

file 'lib/racc/parser-text.rb' => ['lib/racc/parser.rb'] do |t|
  File.open(t.name, 'wb') { |file|
    file.write(<<-eorb)
module Racc
  PARSER_TEXT = <<'__end_of_file__'
  #{File.read(t.prerequisites.first)}
__end_of_file__
end
    eorb
  }
end

task 'ext/racc/cparse/Makefile' do
  Dir.chdir('ext/racc/cparse') do
    ruby "extconf.rb"
  end
end

task EXT => 'ext/racc/cparse/Makefile' do
  Dir.chdir('ext/racc/cparse') do
    sh 'make'
  end
end

task :build => ['lib/racc/parser-text.rb', EXT]

Rake::TestTask.new do |t|
  %w[ ext lib ].each do |dir|
    t.libs << dir
  end

  t.test_files = FileList['test/test_*.rb']
  t.verbose = true
end

Rake::Task[:test].prerequisites << :build

task :default => :test
