# calc.rb make file

RUBY     = ruby ${RUBYFLAG}
RUBYFLAG = 
RUBYPATH = /usr/local/bin/ruby
RACC     = ${RUBY} racc
RFLAG    = -ocalc.rb -e${RUBYPATH} -v
COMPILE  = ${RACC} ${RFLAG}

all: calc.rb

calc.rb: calc.y racc libracc.rb
	${COMPILE} calc.y
	@ echo ""
	@ echo "-------------------------------------"
	@ echo "    calc.rb successfully created."
	@ echo "    Type  ./calc.rb   to test."
	@ echo "-------------------------------------"
	@ echo ""
