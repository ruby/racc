# racc/Makefile

ident   = racc
version = 1.4.5
include $(HOME)/.makeparams

.PHONY: default all test doc update site dist

default: all

all: update lib/racc/parser-text.rb extensions

update:
	update-version --version=$(version) lib/racc/info.rb lib/racc/parser.rb ext/racc/cparse/cparse.c

lib/racc/parser-text.rb: lib/racc/parser.rb
	echo "module Racc" > $@
	echo "PARSER_TEXT = <<'__end_of_file__'" >> $@
	cat lib/racc/parser.rb >> $@
	echo "__end_of_file__" >> $@
	echo "end" >> $@

extensions:
	cd ext/racc/cparse && ruby extconf.rb && $(MAKE)

doc:
	mldoc-split --lang=ja doc/NEWS.rd.m > NEWS.ja
	mldoc-split --lang=en doc/NEWS.rd.m > NEWS.en
	rm -rf doc.ja; mkdir doc.ja
	rm -rf doc.en; mkdir doc.en
	compile-documents --lang=ja --template=$(tmpldir)/manual.ja doc doc.ja
	compile-documents --lang=en --template=$(tmpldir)/manual.en doc doc.en

dist:
	version=$(version) ardir=$(ardir) sh misc/dist.sh

clean:
	rm -f lib/racc/grammarfileparser.rb
	rm -f misc/boot.rb.output
	rm -f lib/racc/parser-text.rb
	rm -rf doc.* NEWS.*
	cd ext/racc/cparse && $(MAKE) clean

test:
	cd test; ruby test.rb

site:
	erb web/racc.ja.rhtml | wrap-html --template=$(tmpldir)/basic.ja | nkf -Ej > $(projdir_ja)/index.html
	erb web/racc.en.rhtml | wrap-html --template=$(tmpldir)/basic.en > $(projdir_en)/index.html
	compile-documents --lang=ja --template=$(tmpldir)/basic.ja doc $(projdir_ja)/doc
	compile-documents --lang=en --template=$(tmpldir)/basic.en doc $(projdir_en)/doc
