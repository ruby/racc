#
# racc runtime library packager
#

require 'amstd/futils'
include FileUtils

def allfile
  ret = []
  Dir.foreach( '.' ) do |i|
    if file? i then
      ret.push i
    end
  end
  ret
end


RACCRT = %w(
  parser.rb
  scanner.rb
)

$target = expand( ARGV[0] )

foreach_fullpath( $target ) do |path|
  rm_rf path
end

cp 'rtsetup.rb', $target + '/setup.rb'

chdir( 'amstd' ) do
  cp allfiles, isdir( $target + '/amstd' )
end

chdir( 'racc' ) do
  cp RACCRT, isdir( $target + '/racc' )

  chdir( 'strscan' ) do
    cp allfiles, isdir( $target + '/strscan' )
  end
  chdir( 'cparse' ) do
    cp allfiles, isdir( $target + '/racc/cparse' )
  end
end
