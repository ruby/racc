#
# facade.rb
#
#   Copyright (c) 1999 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#

require 'amstd/must'


module Racc

  Version = '0.10.9'

class Compiler

  attr :class_name

  attr :parser
  attr :ruletable
  attr :tokentable
  attr :statetable
  attr :formatter
  attr :interf

  attr :logic
  attr :srconf
  attr :rrconf

  attr :dsrc, true

  
  attr :debug,    true
  attr :d_prec,   true
  attr :d_rule,   true
  attr :d_token,  true
  attr :d_state,  true
  attr :d_reduce, true
  attr :d_shift,  true


  def compile( str, fn = '' )
    reset
    parse( str, fn )
    init_rule
    init_state
    resolve
  end

  def reset
    @tokentable = TokenTable.new( self )
    @ruletable  = RuleTable.new( self )
    @interf     = BuildInterface.new( self )
    @parser     = RaccParser.new( self )
    @statetable = LALRstateTable.new( self )
    @formatter  = RaccFormatter.new( self )
  end

  def parse( str, fname = '' )
    str.must String
    @parser.parse( str, fname )
    @class_name = @parser.classname
  end

  def init_rule
    @ruletable.do_initialize( @parser.start )
  end

  def init_state
    @statetable.do_initialize
  end

  def resolve
    @statetable.resolve
  end

  def source( f = '' )
    @formatter.source f
    f
  end

  def output( f = '' )
    @formatter.output_rule  f
    @formatter.output_token f
    @formatter.output_state f
    f
  end


  def initialize
    @logic  = []
    @rrconf = []
    @srconf = []
  end

end


end   # module Racc
