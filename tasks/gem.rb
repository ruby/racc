SPEC = Gem::Specification.new do |s|
  s.platform      = Gem::Platform::RUBY
  s.summary       = "Racc is a LALR(1) parser generator."
  s.name          = 'racc'
  s.authors       << 'Aoki Minero'
  s.authors       << 'Aaron Patterson'
  s.email         = 'aaronp@rubyforge.org'
  s.version       = Racc::VERSION
  s.require_paths = Dir['{lib,ext}']
  s.extensions    = ['ext/racc/extconf.rb']
  s.files         = `git ls-files`.split("\n") + ['lib/racc/parser-text.rb']
  s.homepage      = 'http://racc.rubyforge.org/'
  s.rdoc_options  = ['--main', 'README.en.rdoc']
  s.has_rdoc      = true
  s.rubyforge_project = s.name
  s.executables   = s.files.grep(/^bin/) { |f| File.basename(f) }
  s.bindir        = "bin"
  s.description   = <<EOF
Racc is a LALR(1) parser generator.
It is written in Ruby itself, and generates Ruby program.
EOF
end

SPEC_JAVA = SPEC.dup.tap do |s|
  s.platform      = Gem::Platform.new('java')
  s.extensions    = []
end

namespace :gem do
  namespace :dev do
    task :spec => SPEC.files do
      File.open("#{SPEC.name}.gemspec", 'w') do |f|
        SPEC.version = "#{SPEC.version}.#{Time.now.strftime("%Y%m%d%H%M%S")}"
        f.write(SPEC.to_ruby)
      end
    end
  end
end

Gem::PackageTask.new(SPEC) do |pkg|
  pkg.need_tar = true
end

Gem::PackageTask.new(SPEC_JAVA) do |pkg|
  pkg.need_tar = true
end
