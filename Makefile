
target: calc
RUBYPATH = /usr/local/bin/ruby


TMP  = -v#P

SRC  = d.head.rb   \
       d.facade.rb \
       d.scan.rb   \
       d.parse.rb  \
       d.rule.rb   \
       d.state.rb  \
       d.format.rb \
       parser.rb

TOOL = Makefile bld.rb

CALCFLAGS = -ocalc.rb -e${RUBYPATH} -v

#-------------------------------------------------------------

all: libracc.rb

libracc.rb: ${SRC} ${TOOL}
	./bld.rb &> er || cat er


test: debug
	racc -g -e/usr/local/bin/ruby -ochk.rb chk.y &> er
	./chk.rb

debug: ${SRC} ${TOOL}
	./bld.rb -g &> er || cat er


calc: calc.rb

calc.rb: libracc.rb racc calc.y
	ruby ./racc ${CALCFALGS} calc.y
	@ echo ""
	@ echo "-------------------------------------"
	@ echo "    calc.rb successfully created."
	@ echo "    Type  ./calc.rb   to test."
	@ echo "-------------------------------------"
	@ echo ""

rmcalc:
	rm -f calc.rb calc.output
