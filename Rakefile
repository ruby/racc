# -*- ruby -*-

require "bundler/gem_tasks"

require 'rdoc/task'

RDoc::Task.new(:docs) do |rd|
  spec = Gem::Specification.load("racc.gemspec")
  rd.main = "README.en.rdoc"
  rd.rdoc_files.include(spec.files.find_all { |file_name|
    file_name =~ /^(bin|lib|ext)/ || file_name !~ /\//
  })

  title = "#{spec.name}-#{spec.version} Documentation"

  rd.options << "-t #{title}"
end

def java?
  /java/ === RUBY_PLATFORM
end
def jruby?
  Object.const_defined?(:RUBY_ENGINE) and 'jruby' == RUBY_ENGINE
end

file 'lib/racc/parser-text.rb' => ['lib/racc/parser.rb', __FILE__] do |t|
  source = 'lib/racc/parser.rb'

  text = File.read(source)
  text.gsub!(/^require '(.*)'$/) do
    %[unless $".find {|p| p.end_with?('/#$1.rb')}\n$".push "\#{__dir__}/#$1.rb"\n#{File.read("lib/#{$1}.rb")}\nend\n]
  rescue
    $&
  end
  open(t.name, 'wb') { |io|
    io.write(<<-eorb)
module Racc
  PARSER_TEXT = <<'__end_of_file__'
#{text}
__end_of_file__
end
    eorb
  }
end

if jruby?
  # JRUBY
  require "rake/javaextensiontask"
  extask = Rake::JavaExtensionTask.new("cparse") do |ext|
    jruby_home = RbConfig::CONFIG['prefix']
    ext.lib_dir = 'lib/java/racc'
    ext.ext_dir = 'ext/racc'
    # source/target jvm
    ext.source_version = '1.8'
    ext.target_version = '1.8'
    jars = ["#{jruby_home}/lib/jruby.jar"] + FileList['lib/*.jar']
    ext.classpath = jars.map { |x| File.expand_path x }.join( ':' )
    ext.name = 'cparse-jruby'
  end
else
  # MRI
  require "rake/extensiontask"
  extask = Rake::ExtensionTask.new "cparse" do |ext|
    ext.lib_dir << "/#{RUBY_VERSION}/#{ext.platform}/racc"
    ext.ext_dir = 'ext/racc/cparse'
  end
end

task :compile => ['lib/racc/parser-text.rb']

task :build => "lib/racc/parser-text.rb"

task :test => :compile

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  ENV["RUBYOPT"] = "-I" + [extask.lib_dir, "test/lib"].join(File::PATH_SEPARATOR)
  t.libs << extask.lib_dir
  t.libs << "test/lib"
  t.ruby_opts << "-rhelper"
  t.test_files = FileList["test/**/test_*.rb"]
  if RUBY_VERSION >= "2.6"
    t.ruby_opts << "--enable-frozen-string-literal"
    t.ruby_opts << "--debug=frozen-string-literal" if RUBY_ENGINE != "truffleruby"
  end
end
