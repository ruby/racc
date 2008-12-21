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
