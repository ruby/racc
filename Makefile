#
# racc/Makefile
#

version  = 1.4.4
wcdir    = $(HOME)/c
siteroot = $(HOME)/var/i.loveruby.net/tree
destdir  = $(siteroot)/ja/prog

default: all

all: update
	cd lib/racc && $(MAKE)

update:
	update-version --version=$(version) lib/racc/info.rb

dist:
	version=$(version) sh misc/dist.sh

test:
	cd test; ruby test.rb
	cd test; RUBY=ruby-1.6.8 ruby test.rb

import:
	remove-cvsid amstd $(wcdir)/amstd/rubyloader.rb > lib/racc/rubyloader.rb

site:
