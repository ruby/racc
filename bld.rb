#!/usr/local/bin/ruby

require 'my'
require 'must'
require 'parser'

require './d.rule'
require './d.state'
require './d.format'

class Racc

  attr :ruletable
  attr :statetable
  attr :formatter
  attr :prectable

  def logic()  bug! 'logic called'  end
  def srconf() bug! 'srconf called' end
  def rrconf() bug! 'rrconf called' end

  def dsrc() @dflag end

  def debug() false end
  def d_prec() false end
  def d_rule() false end
  def d_token() false end
  def d_state() false end
  def d_shift() false end
  def d_reduce() false end


  def r( simbol, rarr, act )
		simbol = @interf.get_token( simbol ) if simbol

    rarr.filter do |i|
      bug! 'nil in rulearr' unless i
      @interf.get_token( i )
    end

    @interf.register_rule( simbol, rarr, nil, act )
  end


  def build( debugflag )
	  @dflag = debugflag

    @ruletable  = RuleTable.new( self )
    @statetable = LALRstateTable.new( self )
    @formatter  = RaccFormatter.new( self )

		@interf = BuildInterface.new( self )

############
		# 1
    r :xclass, [ :CLASS, :TOKEN, :params, :RULE, :rules, :XEND ], %{
			@interf.end_register_rule
      @classname = if Integer === val[1] then val[1].id2name else val[1] end
    }
############
		# 2
    r :params, [], ''
		# 3
		r nil, [ :params, :param_seg ], ''
############
		# 4
    r :param_seg, [ :XTOKEN, :tokdefs, :XEND ], %{
      @interf.end_register_conv
		}
		# 5
    r nil, [ :xprec ], ''
		# 6
    r nil, [ :START, :TOKEN ], %{
      if @start then
        raise ParseError, "start rule defined twice"
      end
      @start = @interf.get_token( val[1] )
    }
############
		# 7
    r :tokdefs, [ :toksim, :STRING ], %{
      @interf.register_conv( val[0], val[1] )
		}
		# 8
    r nil, [ :tokdefs, :toksim, :STRING ], %{
      @interf.register_conv( val[1], val[2] )
    }
############
		# 9
    r :xprec, [ :PRECHIGH, :preclines, :PRECLOW ], %{
      @interf.end_register_prec( true )
		}
		# 10
    r nil, [ :PRECLOW, :preclines, :PRECHIGH ], %{
      @interf.end_register_prec( false )
    }
############
		# 11
    r :preclines, [ :precline ], ''
		# 12
    r nil, [ :preclines, :precline ], ''
############
		# 13
    r :precline, [ :LEFT, :tokens_1 ], %{
      @interf.register_prec( :Left, val[1] )
    }
		# 14
    r nil, [ :RIGHT, :tokens_1 ], %{
      @interf.register_prec( :Right, val[1] )
    }
		# 15
    r nil, [ :NONASSOC, :tokens_1 ], %{
      @interf.register_prec( :Nonassoc, val[1] )
    }
############
		# 16
    r :tokens_1, [ :toksim ], %{
      result = val
    }
		# 17
    r nil, [ :tokens_1, :toksim ], %{
      result.push val[1]
    }
############
		# 18
    r :rules, [ :ruleseg, :rulesegterm ], ''
		# 19
    r nil, [ :rules, :ruleseg, :rulesegterm ], ''
############
		# 20
    r :ruleseg, [ :TOKEN, ':', :tokens, :tempprec, :action ], %{
      @interf.register_rule( Token.new(val[0]), val[2], val[3], val[4] )
    }
		# 21
    r nil, [ :ruleseg, '|', :tokens, :tempprec, :action ], %{
      @interf.register_rule( nil, val[2], val[3], val[4] )
    }
############
		# 22
    r :rulesegterm, [ :EOL ], ''
		# 23
    r nil, [ ';' ], ''
############
		# 24
    r :tokens, [], %{
      result = []
    }
		# 25
    r nil, [ :tokens, :toksim ], %{
      result.push val[1]
    }
############
		# 26
		r :toksim, [ :TOKEN ], %{
		  result = @interf.get_token( val[0] )
		}
		# 27
		r nil,     [ :STRING ], %{
			result = @interf.get_token( eval '"' + val[0] + '"' )
    }
############
		# 28
    r :tempprec, [], ''
		# 29
    r nil, [ '=', :toksim ], %{
      result = val[1]
    }
############
		# 30
		r :action, [], %{
		  result = ''
    }
		# 31
		r nil, [ :ACTION ], ''
############

    @ruletable.do_initialize( nil )
    @statetable.do_initialize
    @statetable.resolve

		File.open( 'libracc.rb', 'w' ) do |f|
		  f.write openread( 'd.head.rb' )
			f.puts
			f.write <<SRC
$RACCPARSER_DEBUG = #{ @dflag ? 'true' : 'false' }

class Racc

SRC
      f.write openread( 'd.facade.rb' )
			f.write openread( 'd.scan.rb' )
			f.write openread( 'd.parse.rb' )
			@formatter.source( f )
			f.puts  '  end'
			f.puts
			f.write openread( 'd.rule.rb' )
			f.write openread( 'd.state.rb' )
			f.write openread( 'd.format.rb' )
			f.write 'end'
		end

    File.open( 'b.output', 'w' ) do |f|
      formatter.output_rule f
      formatter.output_token f
      formatter.output_state f
		end
  end

end


Racc.new.build( (ARGV[0] == '-g') )
