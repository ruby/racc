kind  = RbConfig::CONFIG['DLEXT']
EXT   = "ext/racc/cparse.#{kind}"
PTEXT = 'lib/racc/parser-text.rb'

[
  EXT,
  PTEXT,
  'ext/racc/Makefile',
  'ext/racc/*.o',
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

task 'ext/racc/Makefile' do
  Dir.chdir('ext/racc') do
    ruby "extconf.rb"
  end
end

task EXT => 'ext/racc/Makefile' do
  Dir.chdir('ext/racc') do
    sh 'make'
  end
end


task :build => [PTEXT, EXT]
