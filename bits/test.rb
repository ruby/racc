require 'bitmap'

map = Bitmap.new(24)
p map

puts '---- set'
map.set 1
map.set 2
map.set 23
p map

puts '---- size'
p map.size

puts '---- aref'
p map[0]
p map[1]
p map[23]

puts '---- clear'
map.clear
p map

puts '---- update'
map.set 1
map.set 3
map.set 5
m2 = Bitmap.new(24)
m2.set 2
m2.set 4
m2.set 6
m2.set 8
m2.update map
p map
p m2
