
RUBYPATH = /usr/local/bin/ruby
RACC = ruby racc #./racc/racc
.SUFFIXES:

#-------------------------------------------------------------

calc: calc.rb

calc.rb: calc.y
	$(RACC) -o$@ -e$(RUBYPATH) -v calc.y
	@ echo ""
	@ echo "-------------------------------------"
	@ echo "    calc.rb successfully created."
	@ echo "    Type  ./calc.rb   to test."
	@ echo "-------------------------------------"
	@ echo ""

clean:
	rm -f calc.rb calc.output
