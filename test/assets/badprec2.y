class A

prechigh
  left blah
  nonassoc A B C
preclow

token A B C

rule
targ : A B
     | blah

blah: B C

end
