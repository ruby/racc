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

    attr :parser
    attr :ruletable
    attr :symboltable
    attr :statetable
    attr :formatter

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
    attr_accessor :d_la
    attr_accessor :d_prec

    def initialize
      @debug_parser = false
      @verbose      = false
      @make_profile = false
      @convert_line = true
      @omit_action  = true
      @result_var   = true

      @debug   = false
      @d_parse = false
      @d_rule  = false
      @d_token = false
      @d_state = false
      @d_la    = false
      @d_prec  = false
    end

    def parse( str, fname = '-' )
      # must be this order
      @symboltable = SymbolTable.new( self )
      @ruletable   = RuleTable.new( self )
      @parser      = RaccParser.new( self )

      @filename = fname
      @parser.parse( str )
    end

    def compile
      nfa
      dfa
    end

    def nfa
      @statetable = StateTable.new( self )
      @ruletable.init
      @statetable.init
    end

    def dfa
      @statetable.determine
    end

    def source( f = '' )
      fmt = CodeGenerator.new( self )
      fmt.output( f )
      f
    end

    def output( f = '' )
      fmt = VerboseOutputter.new( self )
      fmt.output f
      f
    end

  end

end   # module Racc
