#
# facade.rb
#
#   Copyright (c) 1999,2000 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#
#   This program is free software.
#   You can distribute/modify this program under the terms of
#   the GNU Lesser General Public License version 2 or later.
#

require 'amstd/must'


unless [].respond_to? 'collect!' then
  class Array
    alias collect! filter
  end
end


module Racc

  Version = '1.0.0'

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
  attr :d_line


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
    @d_line    = debugopt[ 'line' ]

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
    @ruletable.init
    @statetable.init
  end

  def dfa
    @statetable.resolve
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
