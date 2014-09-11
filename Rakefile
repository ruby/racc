# -*- ruby -*-

require 'rubygems'
require 'hoe'

gem 'rake-compiler', '>= 0.4.1'

Hoe.plugin :debugging, :doofus, :git, :isolate, :gemspec

def java?
  /java/ === RUBY_PLATFORM
end
def jruby?
  Object.const_defined?(:RUBY_ENGINE) and 'jruby' == RUBY_ENGINE
end

HOE = Hoe.spec 'racc' do
  developer 'Aaron Patterson', 'aaron@tenderlovemaking.com'
  license "MIT"

  self.extra_rdoc_files  = Dir['*.rdoc']
  self.history_file      = 'ChangeLog'
  self.readme_file       = 'README.rdoc'

  dependency 'rake-compiler', '>= 0.4.1', :developer
  dependency 'minitest',      '~> 4.7',   :developer # stick to stdlib's version

  if java?
    self.spec_extras[:platform]   = 'java'
  else
    self.spec_extras[:extensions] = %w[ext/racc/extconf.rb]
  end

  self.clean_globs << "lib/#{self.name}/*.{so,bundle,dll,jar}" # from hoe/compiler

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

file 'lib/racc/parser-text.rb' => ['lib/racc/parser.rb'] do |t|
  source = 'lib/racc/parser.rb'

  open(t.name, 'wb') { |io|
    io.write(<<-eorb)
module Racc
  PARSER_TEXT = <<'__end_of_file__'
#{File.read(source)}
__end_of_file__
end
    eorb
  }
end

unless jruby?
  # MRI
  require "rake/extensiontask"
  Rake::ExtensionTask.new "cparse", HOE.spec do |ext|
    ext.lib_dir = File.join 'lib', 'racc'
    ext.ext_dir = File.join 'ext', 'racc'
  end

  task :compile => 'lib/racc/parser-text.rb'
  #
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

  task :compile => ['lib/racc/parser-text.rb']

  task gem_build_path => [:compile] do
    add_file_to_gem 'lib/racc/cparse-jruby.jar'
  end

end

task :test => :compile

Hoe.add_include_dirs('.:lib/racc')
