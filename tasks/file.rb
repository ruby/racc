kind  = Config::CONFIG['DLEXT']
EXT   = "ext/racc/cparse/cparse.#{kind}"
PTEXT = 'lib/racc/parser-text.rb'

[
  EXT,
  PTEXT,
  'ext/racc/cparse/Makefile',
  'ext/racc/cparse/*.o',
].each { |f| Dir[f].each { |file| CLEAN << file } }

file 'lib/racc/parser.rb'

file PTEXT => 'lib/racc/parser.rb' do |t|
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


task :build => [PTEXT, EXT]
