# This grammar is LR(1), but not LALR(1)

class LrNotLalr

rule
  S: a E a
   | b E b
   | a F b
   | b F a

  E: e
  F: e