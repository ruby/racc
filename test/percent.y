class P
rule
  target: A
      {
        i = 7
        i %= 4
        i.must_be 3
        tmp = %-percent string-
        tmp.must_be 'percent string'
        a = 5; b = 3
        (a%b).must_be 2    #A
      # (a %b).must_be 2    is % string
        (a% b).must_be 2   #B
        (a % b).must_be 2  #C
      }
end

---- inner ----

  def parse
    @q = [[:A, 'A'], [false, '$']]
    do_parse
  end

  def next_token
    @q.shift
  end

---- footer ----

require 'amstd/must'
parser = P.new.parse
