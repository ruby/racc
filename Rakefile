# -*- ruby -*-

require 'rubygems'
require 'hoe'

gem 'rake-compiler'

Hoe.plugin :debugging, :doofus, :git, :gemspec, :bundler

$:.unshift(File.dirname(__FILE__) + '/lib')

def java?
  /java/ === RUBY_PLATFORM
end
def jruby?
  Object.const_defined?(:RUBY_ENGINE) and 'jruby' == RUBY_ENGINE
end

HOE = Hoe.spec 'racc' do
  developer 'Aaron Patterson', 'aaron@tenderlovemaking.com'
  license "LGPL-2.1"

  self.extra_rdoc_files  = Dir['*.rdoc']
  self.readme_file       = 'README.rdoc'

  dependency 'rake',          '~> 12.2',  :developer
  dependency 'rake-compiler', '~> 1.0', :developer
  dependency 'minitest',      '~> 5.10',   :developer

  dependency 'hoe',           '~> 3.16',  :developer
  dependency 'hoe-debugging', '~> 1.4',   :developer
  dependency 'hoe-doofus',    '~> 1.0',   :developer
  dependency 'hoe-git',       '~> 1.6',   :developer
  dependency 'hoe-gemspec',   '~> 1.0',   :developer
  dependency 'hoe-bundler',   '~> 1.3',   :developer

  dependency 'rubocop',       '~> 0.51',  :developer
  dependency 'pry',           '~> 0.11',  :developer

  if java?
    self.spec_extras[:platform]   = 'java'
  else
    self.spec_extras[:extensions] = %w[ext/racc/extconf.rb]
  end

  self.clean_globs << "lib/#{self.name}/*.{so,bundle,dll,jar}" # from hoe/compiler

  require_ruby_version '2.2.8'
end

def add_file_to_gem relative_path
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

unless jruby?
  # MRI
  require "rake/extensiontask"
  Rake::ExtensionTask.new "cparse", HOE.spec do |ext|
    ext.lib_dir = File.join 'lib', 'racc'
    ext.ext_dir = File.join 'ext', 'racc'
  end
else
  # JRUBY
  require "rake/javaextensiontask"
  Rake::JavaExtensionTask.new("cparse", HOE.spec) do |ext|
    jruby_home = RbConfig::CONFIG['prefix']
    ext.lib_dir = File.join 'lib', 'racc'
    ext.ext_dir = File.join 'ext', 'racc'
    # source/target jvm
    ext.source_version = '1.6'
    ext.target_version = '1.6'
    jars = ["#{jruby_home}/lib/jruby.jar"] + FileList['lib/*.jar']
    ext.classpath = jars.map { |x| File.expand_path x }.join( ':' )
    ext.name = 'cparse-jruby'
  end

  task gem_build_path => [:compile] do
    add_file_to_gem 'lib/racc/cparse-jruby.jar'
  end
end

task :test_pure do
  ENV["PURERUBY"] = "1"
  Rake.application[:test].invoke
end

task :test => :compile

require 'rubocop/rake_task'
RuboCop::RakeTask.new(:rubocop) do |task|
  task.options = ['-a', '-D']
end

task :pry, [:grammar_file] do |t, args|
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
