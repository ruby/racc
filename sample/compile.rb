#!/usr/local/bin/ruby

require 'amstd/rbparams'


rubypath = RubyParams::RUBY_PATH
raccpath = './bin/racc/racc'
$cmd     = "ruby #{raccpath} -ocalc.rb -e#{rubypath} %s"


def compile( file )
  if system sprintf( $cmd, file ) then
    print <<S

calc.rb successfuly compiled.
to execute, type "./calc.rb" on command line.

S
  else
    print <<S

compile failed!!!
please bug report to me <aamine@dp.u-netsurf.ne.jp>

S
  end
end


def usage( st )
  print <<S

usage:

  ruby compile.rb [calc|calc2]

S
  exit st
end


case ARGV[0]
when nil, 'calc', 'calc1'
  compile 'calc.y'
when 'calc2', 'jcalc'
  compile 'calc2-ja.y'
when '--help', '-h', '--version', '-v'
  usage 0
else
  usage 1
end
