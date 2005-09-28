#
# racc/Makefile
#

ident    = racc
version  = 1.4.4
include $(HOME)/.makeparams

.PHONY: default all test doc update import site dist

default: all

all: update bootstrap extensions

update:
	update-version --version=$(version) lib/racc/info.rb lib/racc/parser.rb ext/racc/cparse/cparse.c

bootstrap: lib/racc/grammarfileparser.rb
lib/racc/grammarfileparser.rb: misc/boot.rb lib/racc/grammarfileparser.rb.in
	ruby -I./lib misc/boot.rb $@.in > $@

extensions:
	cd ext/racc/cparse && ruby extconf.rb && make

doc:
	mldoc-split --lang=ja doc/NEWS.rd.m > NEWS.ja
	mldoc-split --lang=en doc/NEWS.rd.m > NEWS.en
	rm -rf doc.ja; mkdir doc.ja
	rm -rf doc.en; mkdir doc.en
	compile-documents --lang=ja --template=$(tmpldir)/manual.ja doc doc.ja
	compile-documents --lang=en --template=$(tmpldir)/manual.en doc doc.en

dist:
	version=$(version) sh misc/dist.sh

clean:
	rm -f grammarfileparser.rb b.output
	rm -rf doc.*
	rm -f NEWS.*

test:
	cd test; ruby test.rb

import:
	remove-cvsid --id=amstd $(wcdir)/amstd/rubyloader.rb > lib/racc/rubyloader.rb

site:
	erb web/racc.ja.rhtml | wrap-html --template=$(tmpldir)/basic.ja | nkf -Ej > $(projdir_ja)/index.html
	erb web/racc.en.rhtml | wrap-html --template=$(tmpldir)/basic.en > $(projdir_en)/index.html
	compile-documents --lang=ja --template=$(tmpldir)/basic.ja doc $(projdir_ja)
	compile-documents --lang=en --template=$(tmpldir)/basic.en doc $(projdir_en)
