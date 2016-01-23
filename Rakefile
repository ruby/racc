# -*- ruby -*-

require 'rubygems'
require 'hoe'

gem 'rake-compiler', '>= 0.4.1'

Hoe.plugin :debugging, :doofus, :git, :gemspec, :bundler

$LOAD_PATH.unshift(File.dirname(__FILE__) + '/lib')

def java?
  /java/ =~ RUBY_PLATFORM
end

def jruby?
  Object.const_defined?(:RUBY_ENGINE) && 'jruby' == RUBY_ENGINE
end

HOE = Hoe.spec 'racc' do
  developer 'Aaron Patterson', 'aaron@tenderlovemaking.com'
  license 'MIT'

  self.extra_rdoc_files  = Dir['*.rdoc']
  self.readme_file       = 'README.rdoc'

  dependency 'rake',          '~> 10.4',  :developer
  dependency 'rake-compiler', '>= 0.4.1', :developer
  dependency 'minitest',      '~> 5.8',   :developer

  dependency 'hoe',           '~> 3.14',  :developer
  dependency 'hoe-debugging', '~> 1.2',   :developer
  dependency 'hoe-doofus',    '~> 1.0',   :developer
  dependency 'hoe-git',       '~> 1.6',   :developer
  dependency 'hoe-gemspec',   '~> 1.0',   :developer
  dependency 'hoe-bundler',   '~> 1.2',   :developer

  dependency 'rubocop',       '~> 0.34',  :developer
  dependency 'pry',           '~> 0.10',  :developer

  if java?
    spec_extras[:platform]   = 'java'
  else
    spec_extras[:extensions] = %w(ext/racc/extconf.rb)
  end

  clean_globs << "lib/#{name}/*.{so,bundle,dll,jar}" # from hoe/compiler
end

def add_file_to_gem(relative_path)
  target_path = File.join gem_build_path, relative_path
  target_dir = File.dirname(target_path)
  mkdir_p target_dir unless File.directory?(target_dir)
  rm_f target_path
  safe_ln relative_path, target_path
  HOE.spec.files += [relative_path]
end

def gem_build_path
  File.join 'pkg', HOE.spec.full_name
end

file 'lib/racc/parser-text.rb' => ['lib/racc/parser.rb'] do |t|
  source = 'lib/racc/parser.rb'

  open(t.name, 'wb') do |io|
    io.write(<<-eorb)
# Generated from parser.rb; do not edit
# This file is used for embedding the Racc runtime into a generated parser
module Racc
  PARSER_TEXT = <<'__end_of_file__'
#{File.read(source)}
__end_of_file__
end
    eorb
  end
end

if jruby?
  # JRUBY
  require 'rake/javaextensiontask'
  Rake::JavaExtensionTask.new('cparse', HOE.spec) do |ext|
    jruby_home = RbConfig::CONFIG['prefix']
    ext.lib_dir = File.join 'lib', 'racc'
    ext.ext_dir = File.join 'ext', 'racc'
    # source/target jvm
    ext.source_version = '1.6'
    ext.target_version = '1.6'
    jars = ["#{jruby_home}/lib/jruby.jar"] + FileList['lib/*.jar']
    ext.classpath = jars.map { |x| File.expand_path x }.join(':')
    ext.name = 'cparse-jruby'
  end

  task compile: ['lib/racc/parser-text.rb']

  task gem_build_path => [:compile] do
    add_file_to_gem 'lib/racc/cparse-jruby.jar'
  end
else
  # MRI
  require 'rake/extensiontask'
  Rake::ExtensionTask.new 'cparse', HOE.spec do |ext|
    ext.lib_dir = File.join 'lib', 'racc'
    ext.ext_dir = File.join 'ext', 'racc'
  end

  task compile: 'lib/racc/parser-text.rb'
end

task :test_pure do
  ENV['PURERUBY'] = '1'
  Rake.application[:test].invoke
end

task test: :compile

require 'rubocop/rake_task'
RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ['-a', '-D']
end

task :pry, [:grammar_file] do |_t, args|
  require 'pry'
  require 'racc'
  require 'racc/grammar_file_parser'
  puts "Parsing #{args[:grammar_file]}"
  grammar = Racc::GrammarFileParser.parse_file(args[:grammar_file]).grammar
  grammar.pry
end

Hoe.add_include_dirs('.:lib/racc')

rule '.rb' => '.rl' do |t|
  sh "ragel -F1 -R #{t.source} -o #{t.name}"
end
