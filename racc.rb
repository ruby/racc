#!/usr/local/bin/ruby
#
# racc version 0.9.2
#
#     Copyright (c) 1999 Minero Aoki
#     <aamine@dp.u-netsurf.ne.jp>
#

##### parse arg ------------------------------------------------

require 'parsearg'

def usage
  print <<MESSAGE

usage: racc.rb [ options ] <source file>

  options

    -g   output source for (user) debugging
    -v   verbose mode --- make r.output file
    -c   output only compiled code (not include user code)
    -l   only link files (not compile)
    -P   report simple profile

    -o<outfile>   designate output file name.
                    default '<basename>.tab.rb'
    -e<ruby-path> make executable source file
                    default ruby path '/usr/local/bin/ruby'
    -n<classname> use <classname> for name of parser class
    -i<inner>     use <inner> file for 'inner' code
    -p<prepare>   use <prepare> file for 'prepare' code
    -d<driver>    use <driver> file for 'driver' code

    --version     print version and quit
    --help(-h)    print this message and quit

MESSAGE

end
$USAGE = 'usage'


parseArgs(
  1, nil, "vhPgclG",
  'o:', 'n:', 'i:', 'p:', 'd:', 'e:', 'R:', 'D:', 'X:', 'S:',
  'version', 'help'
)


##### lib --------------------------------------------------


def openread( fname )
  fn = File.expand_path( fname )

  if File.exist? fname then
    f = File.open( fn )
    ret = f.read
    f.close

    return ret
  else
    raise ArgumentError, "no such file: #{fname}"
  end
end


def openwrite( fname, str )
  f = File.open( fname, 'w' )
  f.write str
  f.close
end



def setup_racc( dsrc, dflags )
  rac = Racc.new

  rac.dsrc = true if dsrc
  if dflags then
    rac.debug    = true
    rac.d_prec   = true if /p/io === dflags
    rac.d_rule   = true if /r/io === dflags
    rac.d_token  = true if /t/io === dflags
    rac.d_state  = true if /s/io === dflags
    rac.d_reduce = true if /e/io === dflags
    rac.d_shift  = true if /h/io === dflags
  end

  return rac
end


def load_files( srcs, fnames, tag )
  unless fnames then
    return
  end

  ret = ''
  fnames.split(':').each do |fn|
    ret << openread( fn ) << "\n"
  end
  srcs[ tag ] = ret
end


def make_filename( sfile, suffix )
  temp = sfile.split( '.' )
  if temp.size == 1 then
    return( sfile + suffix )
  else
    temp.pop
    return( temp.join('.') + suffix )
  end
end


RACC_COREFILE = /[^\r\n]+racc generated code/io

def corefile?( fname )
  fn = File.expand_path( fname )
  unless File.exist? fn then
    puts "no such file: #{fname}"
    exit 1
  end

  f = File.open( fn )
  line = f.gets
  f.close

  return (RACC_COREFILE === line)
end




def getvar_link( srcs )
  srcs[ 'core' ] = openread( srcs[ 'cfile' ] )

  sfile = srcs[ 'sfile' ]
  unless sfile then
    return
  end

  srcs[ 'source' ] = src = openread( sfile )

  rac = srcs[ 'racc' ]
  rac.reset
  rac.parse( src, sfile )

  set_codes( srcs, rac )
end


def getvar_compile( srcs, profile )
  sfile = srcs[ 'sfile' ]
  srcs[ 'source' ] = src = openread( sfile )
  rac = srcs[ 'racc' ]

  if profile then
    srcs['core'] = pcompile( rac, srcs )
  else
    srcs['core'] = rac.compile( src, sfile )
  end
  srcs[ 'compiled' ] = true

  set_codes( srcs, rac )
end


def set_codes( srcs, rac )
  srcs[ 'cname' ] = rac.classname
  hash = rac.code
  srcs[ 'psrc' ] = hash['prepare']
  srcs[ 'isrc' ] = hash['inner']
  srcs[ 'dsrc' ] = hash['driver']
end


def pcompile( rac, srcs )
  rac.reset
    times = []
    time = Time.times.utime
    times.push [ 'load', time ]
  rac.parse( srcs['source'], srcs['sfile'] )
    pre = time
    time = Time.times.utime
    times.push [ 'parse', time - pre ]
  rac.init_rule
    pre = time
    time = Time.times.utime
    times.push [ 'caching', time - pre ]
  rac.init_state
    pre = time
    time = Time.times.utime
    times.push [ 'initialize state', time - pre ]
  rac.resolve
    pre = time
    time = Time.times.utime
    times.push [ 'resolve conflicts', time - pre ]
  core = rac.output
    pre = time
    time = Time.times.utime
    times.push [ 'make source', time - pre ]
  
  return core
end




def report_profile( srcs )
  whole = 0
  srcs['profile'].each do |arr|
    whole += arr[1]
  end
  if whole == 0 then whole = 0.01 end

  puts '--task-------------+--sec------+---%-'

  rac.times.each do |n,t|
    print n.ljust(20)
    print pjust( t, 5, 4 )
    puts( (t/whole * 100).to_i.to_s.rjust(5) + '%')
  end

  puts '-------------------+-----------+-----'
  print 'total'.ljust(20)
  puts pjust( whole, 5, 4 )
end

def pjust( num, i, j )
  /(\d+)(\.\d+)?/o === num.to_s
  str = $1.rjust(i)
  if $2 then
    str << $2.ljust(j+1)[0,j+1]
  end

  return str
end




def report_result( rac )

  if rac.logic.size > 0 then
    print "find #{rac.logic.size} logic error\n"
  end

  if rac.rrconf.size > 0 then
    print "find #{rac.rrconf.size} reduce/reduce conflicts\n"
  end

  if rac.srconf.size > 0 then
    print "find #{rac.srconf.size} shift/reduce conflicts\n"
  end
end


def make_output( vfile, rac )
  f = File.open( vfile, 'w' )

  if rac.rrconf.size > 0 then
    f.write rac.rrconf.join("\n")
    f.write "\n"
  end
  if rac.srconf.size > 0 then
    f.write rac.srconf.join("\n")
    f.write "\n"
  end
  if rac.logic.size > 0 then
    f.write rac.logic.join("\n")
    f.write "\n"
  end

  fmt = rac.formatter
  f.write fmt.output_rule
  f.write fmt.output_token
  f.write fmt.output_state

  f.close
end




##### main -------------------------------------------------

if $OPT_R then
  require $OPT_R
else
  require 'libracc'
end


if $OPT_version then
  print "racc version #{Racc::Version}\n"
  exit(0)
end

if $OPT_help or $OPT_h then
  usage ; exit(0)
end


##### set values -------------------------------------------------

def compile( srcs )
  srcs[ 'sfile' ] = ARGV[0]
  $stdout.sync = true if $DEBUG
  getvar_compile( srcs, $OPT_P )
end


srcs = {}
srcs[ 'racc' ] = rac = setup_racc( $OPT_g, $OPT_D )

unless $OPT_l then   # compile
  compile( srcs )

else                 # only link
  case ARGV.size
  when 1
    if corefile? ARGV[0] then
      srcs[ 'cfile' ] = ARGV[0]
      getvar_link( srcs )
    else
      # as no flag

      $stderr.puts "warning: -l flag given, but argv[0] is not corefile"
      compile( srcs )
    end

  when 2
    if corefile? ARGV[0] then
      srcs[ 'cfile' ] = ARGV[0]
      srcs[ 'sfile' ] = ARGV[1]
    elsif corefile? ARGV[1] then
      srcs[ 'cfile' ] = ARGV[1]
      srcs[ 'sfile' ] = ARGV[0]
    else
      puts 'all given files are not Racc core file.'
      exit 1
    end
    getvar_link( srcs )

  else
    $stderr.puts 'too many filenames.'
    exit(1)
  end
end


# over write

load_files( srcs, $OPT_i, 'inner' )
load_files( srcs, $OPT_p, 'prepare' )
load_files( srcs, $OPT_d, 'driver' )
srcs[ 'cname' ] = $OPT_n if $OPT_n


# other var

exe = "#!#{$OPT_e}" if $OPT_e
req = ($OPT_X or 'parser')
sup = ($OPT_S or 'Parser')
out = ($OPT_o or
       make_filename( srcs['sfile'] || srcs['cfile'], '.tab.rb' ))


### make source --------------------------------------------------


if $OPT_c then
  openwrite( out, srcs['core'] )
else
  f = File.open( File.expand_path( out ), 'w' )

  f << exe << "\n\n" if exe
  f << "require '" << req << "'\n"
  f.puts srcs['psrc'].to_s ; f << "\n"

  f << 'class ' <<  srcs['cname'] << ' < ' << sup << "\n\n"
  f.puts srcs['isrc'].to_s
  f.puts srcs['core']
  f << 'end   # class ' << srcs['cname'] << "\n\n"

  f.puts srcs['dsrc'].to_s

  f.close
end


if $OPT_e then
  File.chmod( 0755, out )
else
  File.chmod( 0644, out )
end


##### post process ---------------------------------------------

if srcs[ 'compiled' ] then
  report_result( rac )

  if $OPT_P then
    report_profile( srcs )
  end

  if $OPT_v then
    make_output( make_filename( srcs['sfile'], '.output' ), rac )
  end
end

##### end. ----------------------------------------------------
