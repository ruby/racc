#
# This grammer contains 1 s/r conflict and 1 r/r conflict
#

class A
rule

target : outer

outer  :
       | outer inner

inner  :
       | inner ITEM

end
