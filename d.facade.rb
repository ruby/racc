  Version = '0.9.5'

  attr :code
  attr :classname

  attr :parser
  attr :interf
  attr :prectable
  attr :ruletable
  attr :statetable
  attr :formatter

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


  def compile( str, fname = '' )
    reset
    parse( str, fname )
    init_rule
    init_state
    resolve
    return output
  end


  def reset
    @ruletable  = RuleTable.new( self )
    @interf     = BuildInterface.new( self )
    @code       = {}
    @parser     = RaccParser.new( self )
    @statetable = LALRstatTable.new( self )
    @formatter  = RaccFormatter.new( self )
  end

  def parse( str, fname = '' )
    str.must String
    @parser.parse( str, fname )
    @classname = @parser.classname
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

  def output
    @formatter.source
  end


  def initialize
    @logic  = []
    @rrconf = []
    @srconf = []
  end

