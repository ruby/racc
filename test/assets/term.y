class Parse
rule
  target    : term
                { p 'target:term' }
  term      : :TERM1
                { p 'term:TERM1' }
            | :TERM2
                { p 'term:TERM2' }
            | term :TERM3
                { p 'term:TERM3' }
end
