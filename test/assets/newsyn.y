
class A

  convert
    left 'a'
    right 'b'
    preclow 'c'
    nonassoc 'd'
    preclow 'e'
    prechigh 'f'
  end

rule

  left: right nonassoc preclow prechigh

  right: A B C

end
