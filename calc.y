
class Calcp

  prechigh
    nonassoc UMINUS
    left '*' '/'
    left '+' '-'
  preclow

  rule
    target: exp .
      .
      |
      .
        result = 0
      .
      ;

    exp: exp '+' exp . result += val[2]
       .
       | exp '-' exp . result -= val[2]
       .
       | exp '*' exp . result *= val[2]
       .
       | exp '/' exp . result /= val[2]
       .
       | '(' exp ')' . result = val[1]
       .
       | '-' NUMBER  = UMINUS . result = -val[1]
       .
       | NUMBER .
       .
       ;
  end

end # class

prepare = code
require 'must'
.

inner = code
  
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
.


driver = code

class Nemui < Exception ; end

parser = Calcp.new
count = 0
scnt  = 0

print "\n***********************"
print "\n超豪華お役だち電卓2号機"
print "\n***********************\n\n"
print "帰りたくなったらQをタイプしてね\n"

while true do
  print "\n"
  print 'ikutu? > '
  str = gets.chop!
  if /\Aq/io === str then break end

  begin
    val = parser.parse( str )
    print 'kotae! = ', val, "\n"
    scnt += 1
    
    case scnt
    when 5
      print "\n働きものでしょっ 5回も計算しちゃった！\n\n"
    when 10
      print "\nいっぱい計算するんだね…\n\n"
    when 15
      print "\nねえーっ もうつかれたー！ もう休もうよー\n\n"
    when 20
      print "\nもうねるのっ！！\n\n"
      raise Nemui, "もうだめ。"
    end

  rescue ParseError
    case count
    when 0
      print "\n  いじわるっ！\n"
    when 1
      print "\n  もうっ、おこっちゃうよ！！\n"
    when 2
      print "\n  もう許してあげないんだからっ！！！\n\n\n"
      sleep(0.5)
      print "           えいっ☆\n\n"
      sleep(1)
      raise
    end
    count += 1

  rescue
    print "\n  さよなら…\n"
    raise

  end

end

print "\nじゃあ、またねっ\n\n"
sleep(0.5)

.

