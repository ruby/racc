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


class Compiler

  attr :filename
  attr :class_name

  attr :parser
  attr :ruletable
  attr :tokentable
  attr :statetable
  attr :formatter
  attr :interf

  attr_accessor :debug_parser
  attr_accessor :verbose
  attr_accessor :make_profile
  attr_accessor :convert_line
  attr_accessor :omit_action
  attr_accessor :result_var
  
  attr_accessor :debug
  attr_accessor :d_parse
  attr_accessor :d_rule
  attr_accessor :d_token
  attr_accessor :d_state
  attr_accessor :d_reduce
  attr_accessor :d_shift

  def initialize
    @debug_parser = false
    @verbose      = false
    @make_profile = false
    @convert_line = true
    @omit_action  = true
    @result_var   = true

    @debug    = nil
    @d_parse  = nil
    @d_rule   = nil
    @d_token  = nil
    @d_state  = nil
    @d_reduce = nil
    @d_shift  = nil
  end

  def parse( str, fname = '-' )
    @tokentable = TokenTable.new( self )
    @ruletable  = RuleTable.new( self )
    @interf     = BuildInterface.new( self )
    @parser     = RaccParser.new( self )

    @filename = fname
    @parser.parse( str )
    @class_name = @parser.classname
  end

  def compile
    nfa
    dfa
  end

  def nfa
    @statetable = LALRstateTable.new( self )
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
