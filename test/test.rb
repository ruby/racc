#!/usr/local/bin/ruby

require 'amstd/must'
require 'amstd/bug'
require 'fileutils'

include FileUtils

def clean( dir )
  rm_rf dir
  mkdir dir
end


def try( args, ok, exec = false )
  targ = args[0].split('.')[0]
  testing( targ ) {
    compile_test args, ok
    if exec then
      testing( targ ) {
        exec_test targ
      }
    end
  }
end

clean 'log'
clean 'tab'
clean 'out'

def compile_test( args, chk )
  fname = args.shift
  n = fname.sub(/\.y\z/, '')
  args.push '-Oout/' + n
  args.push '-otab/' + n
  args.unshift '-Dapo'
  args.push fname

  racc args.join(' ')
  File.foreach( "log/#{fname}" ) do |line|
    line.strip!
    case line
    when /sr/ then line.must_be "sr#{chk[0]}"
    when /rr/ then line.must_be "rr#{chk[1]}"
    when /un/ then line.must_be "un#{chk[2]}"
    when /ur/ then line.must_be "ur#{chk[3]}"
    when /ex/ then line.must_be "ex#{chk[4]}"
    else
      raise TestError, 'racc outputs unknown debug report???'
    end
  end
end

def exec_test( file )
  ruby 'tab/' + file
end

def must_fail( file )
  testing( file.split('.')[0] ) {
    begin
      racc file
    rescue TestError
    else
      raise TestError, 'error not raised'
    end
  }
end


class TestError < StandardError; end

@n_test = 0
@n_ok = 0
@errors = []
@target = nil

def testing( name )
  return unless target? name
  @target = name

  $stderr.print '.'
  @n_test += 1
  begin
    yield
    @n_ok += 1
  rescue TestError => err
    $stderr.print 'F'
    @errors.push [@target, err.message]
  end
end

def target?( name )
  ARGV.empty? or ARGV.include? name
end

def report
  if @n_test == @n_ok then
    printf "\nOK %d/%d tests\n", @n_ok, @n_test
  else
    printf "\n%d errors\n", @errors.size
    @errors.each do |targ, msg|
      puts targ + ' fail: ' + msg
    end
  end
end


$ruby = ENV['RUBY'] || 'ruby'
$racc = 'racc'
$racc += ' --no-extentions' if ENV['NORUBYEXT']

clean 'err'

def ruby( arg )
  cmd = "#{$ruby} #{arg}"
  str = "#{cmd} 2>> err/#{@target}"
  # $stderr.puts str
  system str or raise TestError, "'#{cmd}' failed"
end

def racc( arg )
  ruby "-S #{$racc} #{arg}"
end


try %w( syntax.y -v               ), [0,0,0,0,0]
try %w( percent.y                 ), [], true
try %w( scan.y                    ), [], true
try %w( newsyn.y                  ), []
try %w( normal.y                  ), []
try %w( normal.y -vg              ), []
try %w( chk.y    -vg              ), [], true
try %w( chk.y    -c               ), [], true
try %w( echk.y   -E               ), [], true
try %w( err.y                     ), [], true
try %w( mailp.y                   ), []
try %w( conf.y   -v               ), [4,1,1,2]
try %w( rrconf.y                  ), [1,1,0,0]
try %w( useless.y                 ), [0,0,1,2]
try %w( opt.y                     ), [], true
try %w( yyerr.y                   ), [], true
try %w( recv.y                    ), [5,10,1,4]
try %w( ichk.y                    ), [], true
try %w( intp.y                    ), [], true
try %w( expect.y                  ), [1,0,0,0,1]
try %w( nullbug1.y                ), [0,0,0,0]
try %w( nullbug2.y                ), [0,0,0,0]
try %w( firstline.y               ), []
try %w( nonass.y                  ), [], true
try %w( digraph.y                 ), [], true
try %w( noend.y                   ), []
must_fail 'norule.y'
must_fail 'unterm.y'
report
