#
# racc/Makefile
#

version  = 1.4.3
siteroot = $(HOME)/var/i.loveruby.net/tree
destdir  = $(siteroot)/ja/prog
wcdir    = $(HOME)/c

default: all

all: update
	cd lib/racc && $(MAKE)

update:
	update-version --version=$(version) lib/racc/info.rb

dist:
	rm -rf tmp
	mkdir tmp
	cd tmp; cvs -Q export -r`echo V$(version) | tr . -` -d racc-$(version) racc
	cd tmp/racc-$(version)/lib/racc; make
	cp $(datadir)/setup.rb tmp/racc-$(version)
	cp $(datadir)/LGPL tmp/racc-$(version)/COPYING
	cd tmp; tar czf $(ardir)/racc-$(version).tar.gz racc-$(version)
	rm -rf tmp

import:
	remove-cvsid amstd $(wcdir)/amstd/rubyloader.rb > lib/racc/rubyloader.rb
