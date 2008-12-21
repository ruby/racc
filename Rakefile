require 'rake'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'rake/testtask'
require 'rake/clean'

$: << File.expand_path(File.join(File.dirname(__FILE__), "lib"))
require 'lib/racc/parser'

kind = Config::CONFIG['DLEXT']

EXT = "ext/racc/cparse/cparse.#{kind}"
[
  EXT,
  'lib/racc/parser-text.rb',
  'ext/racc/cparse/Makefile',
  'ext/racc/cparse/*.o',
].each { |f| Dir[f].each { |file| CLEAN << file } }

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

PKG_FILES = `git ls-files`.split("\n") + ['lib/racc/parser-text.rb']

spec = Gem::Specification.new do |s|
  s.platform      = Gem::Platform::RUBY
  s.summary       = "Racc is a LALR(1) parser generator."
  s.name          = 'racc'
  s.authors       << 'Aoki Minero'
  s.authors       << 'Aaron Patterson'
  s.email         = 'aaronp@rubyforge.org'
  s.version       = Racc::Parser::Racc_Runtime_Version
  s.require_paths = Dir['{lib,ext}']
  s.extensions    = ['ext/racc/cparse/extconf.rb']
  s.files         = PKG_FILES
  s.homepage      = 'http://racc.rubyforge.org/'
  s.rubyforge_project = s.name
  s.executables   = s.files.grep(/^bin/) { |f| File.basename(f) }
  s.bindir        = "bin"
  s.description = <<EOF
Racc is a LALR(1) parser generator.
It is written in Ruby itself, and generates Ruby program.
EOF
end

namespace :gem do
  namespace :dev do
    task :spec => PKG_FILES do
      File.open("#{spec.name}.gemspec", 'w') do |f|
        spec.version = "#{spec.version}.#{Time.now.strftime("%Y%m%d%H%M%S")}"
        f.write(spec.to_ruby)
      end
    end
  end
end

namespace :test do
  task :multi do
    sh 'multiruby -S rake clean test'
  end
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
