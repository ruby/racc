#
# racc tester
#

class Calcp

  prechigh
    left '*' '/'
    left '+' '-'
  preclow

  convert
    NUMBER 'Number'
  end

rule

  target : exp | /* none */ { result = 0 } ;

  exp    : exp '+' exp { result += val[2]; a = 'plus' }
         | exp '-' exp { result -= val[2]; "string test" }
         | exp '*' exp { result *= val[2] }
         | exp '/' exp { result /= val[2] }
         | '(' { $emb = true } exp ')'
             {
               raise 'must not happen' unless $emb
               result = val[2]
             }
         | '-' NUMBER  { result = -val[1] }
         | NUMBER
         ;

end

----header

class Number; end

----inner

  def parse( src )
    @src = src
    @racc_debug_out = $stdout
    yyparse self, :scan
  end

  def scan( &block )
    @src.each &block
  end

  def initialize
    @yydebug = true
  end

----footer

$parser = Calcp.new
$test_number = 1

def chk( src, ans )
  result = $parser.parse( src )
  raise "test #{$test_number} fail" unless result == ans
  $test_number += 1
end

chk(
  [ [Number, 9],
    [false, '$'] ], 9
)

chk(
  [ [Number, 5],
    ['*',   '*'],
    [Number, 1],
    ['-',   '*'],
    [Number, 1],
    ['*',   '*'],
    [Number, 8],
    [false, '$'] ], -3
)

chk(
  [ [Number, 5],
    ['+',   '+'],
    [Number, 2],
    ['-',   '-'],
    [Number, 5],
    ['+',   '+'],
    [Number, 2],
    ['-',   '-'],
    [Number, 5],
    [false, '$'] ], -1
)

chk(
  [ ['-',    'UMINUS'],
    [Number, 4],
    [false, '$'] ], -4
)

chk(
  [ [Number, 7],
    ['*',   '*'],
    ['(',   '('],
    [Number, 4],
    ['+',   '+'],
    [Number, 3],
    [')',   ')'],
    ['-',   '-'],
    [Number, 9],
    [false, '$'] ], 40
)
