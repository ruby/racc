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

  exp    : exp '+' exp { result += val[2]; @plus = 'plus' }
         | exp '-' exp { result -= val[2]; @str = "string test" }
         | exp '*' exp { result *= val[2] }
         | exp '/' exp { result /= val[2] }
         | '(' { $emb = true } exp ')'
             {
               bug! unless $emb
               result = val[2]
             }
         | '-' NUMBER  { result = -val[1] }
         | NUMBER
         ;

end

------ prepare -----------------------------

require 'amstd/bug'

class Number ; end

------ inner -------------------------------

  def parse( src )
    $emb = false
    @plus = @str = nil

    @src = src
    ret = do_parse
    if @plus then
      @plus == 'plus' or bug! 'string parse failed'
    end
    if @str then
      @str == 'string test' or bug! 'string parse failed'
    end

    ret
  end

  def next_token
    @src.shift
  end

  def initialize
    @yydebug = true
  end

------ driver -------------------------------

$parser = Calcp.new
$tidx = 1

def chk( src, ans )
  ret = $parser.parse( src )
  unless ret == ans then
    bug! "test #{$tidx} fail"
  end
  $tidx += 1
end

chk(
  [ [Number, 9],
    [false, false],
    [false, false] ], 9
)

chk(
  [ [Number, 5],
    ['*', nil],
    [Number, 1],
    ['-', nil],
    [Number, 1],
    ['*', nil],
    [Number, 8],
    [false, false],
    [false, false] ], -3
)

chk(
  [ [Number, 5],
    ['+', nil],
    [Number, 2],
    ['-', nil],
    [Number, 5],
    ['+', nil],
    [Number, 2],
    ['-', nil],
    [Number, 5],
    [false, false],
    [false, false] ], -1
)

chk(
  [ ['-', nil],
    [Number, 4],
    [false, false],
    [false, false] ], -4
)

chk(
  [ [Number, 7],
    ['*', nil],
    ['(', nil],
    [Number, 4],
    ['+', nil],
    [Number, 3],
    [')', nil],
    ['-', nil],
    [Number, 9],
    [false, false],
    [false, false] ], 40
)
