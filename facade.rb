#
# facade.rb
#
#   Copyright (c) 1999 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#

require 'amstd/must'


module Racc

  Version = '0.14.4'

class Compiler

  attr :class_name

  attr :parser
  attr :ruletable
  attr :tokentable
  attr :statetable
  attr :formatter
  attr :interf

  attr :dsrc
  
  attr :debug
  attr :d_prec
  attr :d_rule
  attr :d_token
  attr :d_state
  attr :d_reduce
  attr :d_shift
  attr :d_verbose
  attr :d_profile


  def initialize( debugopt )
    @dsrc      = debugopt[ 'debug-src' ]

    @debug     = debugopt[ 'debug' ]
    @d_prec    = debugopt[ 'prec' ]
    @d_rule    = debugopt[ 'rule' ]
    @d_token   = debugopt[ 'token' ]
    @d_state   = debugopt[ 'state' ]
    @d_reduce  = debugopt[ 'reduce' ]
    @d_shift   = debugopt[ 'shift' ]
    @d_verbose = debugopt[ 'verbose' ]
    @d_profile = debugopt[ 'profile' ]

    @tokentable = TokenTable.new( self )
    @ruletable  = RuleTable.new( self )
    @interf     = BuildInterface.new( self )
    @parser     = RaccParser.new( self )
    @statetable = LALRstateTable.new( self )
  end

  def compile( str, fn = '' )
    parse( str, fn )
    nfa
    dfa
  end

  def parse( str, fname = '' )
    @parser.parse( str, fname )
    @class_name = @parser.classname
  end

  def nfa
    GC.disable
    @ruletable.init
    @tokentable.init
    @statetable.init
    GC.enable
    GC.start
  end

  def dfa
    GC.disable
    @statetable.resolve
    GC.enable
    GC.start
  end

  def alist_table( f = '' )
    fmt = AListTableGenerator.new( self )
    fmt.output( f )
    f
  end

  def index_table( f = '' )
    fmt = IndexTableGenerator.new( self )
    fmt.output( f )
    f
  end

  alias source index_table

  def output( f = '' )
    fmt = VerboseOutputFormatter.new( self )
    fmt.output f
    f
  end

end


end   # module Racc
