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
      i or bug! 'nil in rulearr'
      @interf.get_token( i )
    end

    @interf.register_rule(
      simbol,
      rarr,
      nil,
      act
    )
  end


  def build( debugflag )
	  @dflag = debugflag

    @ruletable  = RuleTable.new( self )
    @statetable = LALRstatTable.new( self )
    @formatter  = RaccFormatter.new( self )

		@interf = BuildInterface.new( self )

############
    r :xclass, [ :CLASS, :TOKEN, :clsentity, :XEND ], <<SRC
      @classname = val[1].to_s
SRC
############
    r :clsentity, [], ''
    r nil, [ :clsentity, :RULE, :rules, :XEND ], <<SRC
      @interf.end_register_rule
SRC
    r nil, [ :clsentity, :XTOKEN, :tokdefs, :XEND ], <<SRC
      @interf.end_register_conv
SRC
    r nil, [ :clsentity, :xprec ], ''
    r nil, [ :clsentity, :START, :TOKEN ], <<SRC
      if @start then
        raise ParseError, "start rule defined twice"
      end
      @start = val[1]
SRC
############
    r :tokdefs, [ :toksim, :STRING ], <<SRC
      @interf.register_conv( val[0], val[1] )
SRC
    r nil, [ :tokdefs, :toksim, :STRING ], <<SRC
      @interf.register_conv( val[1], val[2] )
SRC
############
    r :xprec, [ :PRECHIGH, :preclines, :PRECLOW ], <<SRC
      @interf.end_register_prec( true )
SRC
    r nil, [ :PRECLOW, :preclines, :PRECHIGH ], <<SRC
      @interf.end_register_prec( false )
SRC
############
    r :preclines, [ :precline ], ''
    r nil, [ :preclines, :precline ], ''
############
    r :precline, [ :LEFT, :tokens ], <<SRC
      @interf.register_prec( :Left, val[1] )
SRC
    r nil, [ :RIGHT, :tokens ], <<SRC
      @interf.register_prec( :Right, val[1] )
SRC
    r nil, [ :NONASSOC, :tokens ], <<SRC
      @interf.register_prec( :Nonassoc, val[1] )
SRC
############
    r :rules, [ :ruleseg, :rulesegterm ], ''
    r nil, [ :rules, :ruleseg, :rulesegterm ], ''
############
    r :rulesegterm, [ :EOL ], ''
    r nil, [ ';' ], ''
############
    r :ruleseg, [ :TOKEN, ':', :tokens, :tempprec, :action ], <<SRC
      @interf.register_rule( val[0], val[2], val[3], val[4] )
SRC
    r nil, [ :ruleseg, '|', :tokens, :tempprec, :action ], <<SRC
      @interf.register_rule( nil, val[2], val[3], val[4] )
SRC
############
    r :tokens, [], <<SRC
      result = []
SRC
    r nil, [ :tokens, :toksim ], <<SRC
      result.push val[1]
SRC
############
		r :toksim, [ :TOKEN ], ''
		r nil,     [ :STRING ], <<SRC
			result = @interf.get_token( eval '"' + val[0] + '"' )
SRC
############
    r :tempprec, [], ''
    r nil, [ '=', :toksim ], <<SRC
      result = val[1]
SRC
############
		r :action, [], <<SRC
		  result = ''
SRC
		r nil, [ :ACTION ], ''
############

    @ruletable.do_initialize( nil )
    @statetable.do_initialize
    @statetable.resolve
    src = @formatter.source


    openwrite( 'libracc.rb', <<SOURCE )
#{openread( 'd.head.rb' )}

$RACCPARSER_DEBUG = #{ @dflag ? 'true' : 'false' }

class Racc

#{openread( 'd.facade.rb' )}
#{openread( 'd.scan.rb' )}
#{openread( 'd.parse.rb' )}
#{src}
  end
#{openread( 'd.rule.rb' )}
#{openread( 'd.state.rb' )}
#{openread( 'd.format.rb' )}
end
SOURCE

    openwrite( 'b.output', <<SOURCE )
#{formatter.output_rule}
#{formatter.output_token}
#{formatter.output_state}
SOURCE

  end

end


Racc.new.build( (ARGV[0] == '-g') )
