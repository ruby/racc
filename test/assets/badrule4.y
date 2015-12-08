class A
rule
  A : a { puts 'hello' } b c
    | a b { puts 'hello' } c
end
