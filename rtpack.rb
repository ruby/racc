
RACC   = %w( parser.rb )
CPARSE = %w( cparse.c depend MANIFEST extconf.rb )


require 'amstd/futils'
include FileUtils

$target = expand( ARGV[0] )

foreach_fullpath( $target ) do |path|
  rm_rf path
end

cp 'rtsetup.rb', $target + '/setup.rb'

chdir( 'amstd' ) do
  dn = isdir( $target + '/amstd' )
  foreach_fullpath( '.' ) do |fn|
    cp fn, dn if file? fn
  end
end

chdir( 'racc' ) do
  cp RACC, isdir( $target + '/racc' )

  chdir( 'cparse' ) do
    cp CPARSE, isdir( $target + '/racc/cparse' )
  end
end
