
class Calcp

  prechigh
    left '*' '/'
    left '+' '-'
  preclow

  token
    NUMBER 'Number'
  end

rule

	target: exp | /* none */ { result = 0 } ;

	exp: exp '+' exp { result += val[2] ; a = 'plus' }
		 | exp '-' exp { result -= val[2] ; "string test" }
		 | exp '*' exp { result *= val[2] }
		 | exp '/' exp { result /= val[2] }
		 | '(' exp ')' { result = val[1]  }
		 | '-' NUMBER  { result = -val[1] }
		 | NUMBER
		 ;

end



------ prepare -----------------------------

class Number ; end


------ inner -------------------------------

  def parse( tsrc, vsrc )
    @token_source = tsrc
    @value_source = vsrc

    do_parse
  end

  def next_token
    @token_source.shift
  end

  def next_value
    @value_source.shift
  end

  def peep_token
    @token_source[0]
  end      

	def initialize
	  #@__debug__ = true
	end



------ driver -------------------------------

$parser = Calcp.new
$tidx = 1

def chk( sar, var, exp )
  ret = $parser.parse( sar, var )
  unless ret == exp then
    bug! "test #{$tidx} fail"
  end
  $tidx += 1
end

chk(
  [ Number, false, false ],
  [ 9, false, false ],
  9
)

chk(
  [ Number, '*', Number, '-', Number, '*', Number, false, false ],
  [ 5, nil, 1, nil, 1, nil, 8 ],
  -3
)

chk(
  [ Number, '+', Number, '-', Number, '+', Number, '-', Number,
	  false, false ],
	[ 5, nil, 2, nil, 5, nil, 2, nil, 5 ],
	-1
)

chk(
  [ '-', Number, false, false ],
	[ nil, 4 ],
	-4
)

chk(
  [ Number, '*', '(', Number, '+', Number, ')', '-', Number, false, false ],
	[ 7, nil, nil, 4, nil, 3, nil, nil, 9 ],
	40
)

print "\n\ntest ok\n\n"
