
class Bench

rule

  target: a a a a a   a a a a a;
  a:      b b b b b   b b b b b;
  b:      c c c c c   c c c c c;
  c:      d d d d d   d d d d d;
  d:      e e e e e   e e e e e;

end

---- inner

def initialize
  @old = [ :e, 'e' ]
  @i = 0
end

def next_token
  return [false, '$'] if @i >= 10_0000
  @i += 1
  @old
end

def parse
  do_parse
end

---- footer

require 'amstd/bench'

p = Bench.new
benchmark( 'do', 1 ) {
  p.parse
}
