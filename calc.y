
# simple calc parser

class Calcp

  prechigh
    nonassoc UMINUS
    left '*' '/'
    left '+' '-'
  preclow

rule

	target: exp
				| /* none */ { result = 0 }
				;

	exp: exp '+' exp { result += val[2] }
		 | exp '-' exp { result -= val[2] }
		 | exp '*' exp { result *= val[2] }
		 | exp '/' exp { result /= val[2] }
		 | '(' exp ')' { result = val[1] }
		 | '-' NUMBER  = UMINUS { result = -val[1] }
		 | NUMBER
		 ;

end


---- prepare ----
require 'must'


---- inner ----
  
  def parse( str )
    str.must String
    @tsrc = []
    @vsrc = []

    while str.size > 0 do
      case str
      when /\A\s+/o
      when /\A\d+/o
        @tsrc.push :NUMBER
        @vsrc.push $&.to_i
      when /\A.|\n/o
        s = $&
        @tsrc.push s
        @vsrc.push s
      end
      str = $'
    end
        
    @tsrc.push false
    @tsrc.push false
    @vsrc.push false
    @vsrc.push false

    do_parse
  end

  def next_token
    @tsrc.shift
  end

  def next_value
    @vsrc.shift
  end

  def peep_token
    @tsrc[0]
  end      


---- driver ----

parser = Calcp.new
count = 0
scnt  = 0

puts
puts 'type "Q" to quit.'
puts

while true do
  print "\n"
  print '? '
  str = gets.chop!
  if /q/io === str then break end

  begin
    val = parser.parse( str )
    print '= ', val, "\n"
  rescue ParseError
    puts $!
  rescue
    puts 'unexpected error?!'
    raise
  end

end
