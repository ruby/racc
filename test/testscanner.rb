#
# racc scanner tester
#

require 'racc/raccs'


class ScanError < StandardError; end

def testdata
  Dir.glob( File.dirname($0) + '/scandata/*' ) -
  Dir.glob( File.dirname($0) + '/scandata/*.swp' )
end

testdata().each do |file|
  $stderr.print File.basename(file) + ': '
  begin
    ok = File.read(file)
    s = Racc::RaccScanner.new( ok )
    sym, (val, lineno) = s.scan
    val = '{' + val + "}\n"
    :ACTION == sym or raise ScanError, 'is not action!'
    val == ok or raise ScanError,
        "data not same\n>>>\n" + ok + "----\n" + val + '<<<'

    $stderr.puts 'ok'
  rescue => err
    $stderr.puts 'fail (' + err.type.to_s + ')'
    $stderr.puts err.message
    $stderr.puts err.backtrace
    $stderr.puts
  end
end
