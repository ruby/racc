#
# racc/Makefile
#

version  = 1.4.4
wcdir    = $(HOME)/c
tmpldir  = $(HOME)/share/template
siteroot = $(HOME)/var/i.loveruby.net/tree

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
	install-html --template=$(tmpldir)/basic.tmpl.ja web/racc.ja.html $(siteroot)/ja/prog
	install-html --template=$(tmpldir)/basic.tmpl.en web/racc.en.html $(siteroot)/en
