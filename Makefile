#
# racc/Makefile
#

version  = 1.4.4
siteroot = $(HOME)/var/i.loveruby.net/tree
destdir  = $(siteroot)/ja/prog
datadir  = $(HOME)/share
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

test:
	cd test; ruby test.rb
	cd test; RUBY=ruby-1.6.8 ruby test.rb

import:
	remove-cvsid amstd $(wcdir)/amstd/rubyloader.rb > lib/racc/rubyloader.rb
