#
# print scan result
#

require 'racc/raccs'
$raccs_print_type = true


class ScanError < StandardError; end

def testdata
  Dir.glob( File.dirname($0) + '/scandata/*' ) -
  Dir.glob( File.dirname($0) + '/scandata/*.swp' )
end

testdata().each do |file|
  $stderr.puts File.basename(file)
  ok = File.read(file)
  s = Racc::RaccScanner.new( ok )
  sym, (val, lineno) = s.scan
  puts val
end
