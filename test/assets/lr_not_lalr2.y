
class LrNotLalr2

rule
  S: '('  X
   |  E  ']'
   |  F  ')'

  X:  E  ')'
  |   F  ']'

  E: A
  F: A

  A: # null