#
# racc/Makefile
#

version  = 1.4.4
wcdir    = $(HOME)/c
datadir  = $(HOME)/share
tmpldir  = $(HOME)/share/template
siteroot = $(HOME)/var/i.loveruby.net/tree

.PHONY: default all test doc update import site dist

default: all

all: update
	cd lib/racc && $(MAKE)
	cd ext/racc/cparse && ruby extconf.rb && make

update:
	update-version --version=$(version) lib/racc/info.rb lib/racc/parser.rb ext/racc/cparse/cparse.c

doc:
	mldoc-split --lang=ja doc/NEWS.rd.m > NEWS.ja
	mldoc-split --lang=en doc/NEWS.rd.m > NEWS.en
	rm -rf doc.ja; mkdir doc.ja
	rm -rf doc.en; mkdir doc.en
	compile-documents --ja --template=$(tmpldir)/manual.tmpl.ja --nocode=$(datadir)/NOCODE --refrdrc=$(datadir)/refrdrc.ja doc doc.ja
	compile-documents --en --template=$(tmpldir)/manual.tmpl.en --nocode=$(datadir)/NOCODE doc doc.en

dist:
	version=$(version) sh misc/dist.sh

clean:
	rm -rf doc.*
	rm -f NEWS.*
	cd lib/racc; $(MAKE) clean

test:
	cd test; ruby test.rb
	cd test; RUBY=ruby-1.6.8 ruby test.rb

import:
	remove-cvsid amstd $(wcdir)/amstd/rubyloader.rb > lib/racc/rubyloader.rb

site:
	install-html --template=$(tmpldir)/basic.tmpl.ja web/racc.ja.html $(siteroot)/ja/prog
	install-html --template=$(tmpldir)/basic.tmpl.en web/racc.en.html $(siteroot)/en
	compile-documents --ja --template=$(tmpldir)/basic.tmpl.ja --nocode=$(datadir)/NOCODE --refrdrc=$(datadir)/refrdrc.ja doc $(siteroot)/ja/man/racc
	compile-documents --en --template=$(tmpldir)/basic.tmpl.en --nocode=$(datadir)/NOCODE doc $(siteroot)/en/man/racc
