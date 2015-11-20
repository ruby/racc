# Ruby is copyrighted free software by Yukihiro Matsumoto <matz@netlab.jp>.
# You can redistribute it and/or modify it under either the terms of the GPL
# version 2 (see https://github.com/uwabami/rdtool/blob/master/COPYING.txt),
# or the conditions below:
#
#   1. You may make and give away verbatim copies of the source form of the
#      software without restriction, provided that you duplicate all of the
#      original copyright notices and associated disclaimers.
#
#   2. You may modify your copy of the software in any way, provided that
#      you do at least ONE of the following:
#
#        a) place your modifications in the Public Domain or otherwise
#           make them Freely Available, such as by posting said
#           modifications to Usenet or an equivalent medium, or by allowing
#           the author to include your modifications in the software.
#
#        b) use the modified software only within your corporation or
#           organization.
#
#        c) rename any non-standard executables so the names do not conflict
#           with standard executables, which must also be provided.
#
#        d) make other distribution arrangements with the author.
#
#   3. You may distribute the software in object code or executable
#      form, provided that you do at least ONE of the following:
#
#        a) distribute the executables and library files of the software,
#           together with instructions (in the manual page or equivalent)
#           on where to get the original distribution.
#
#        b) accompany the distribution with the machine-readable source of
#           the software.
#
#        c) give non-standard executables non-standard names, with
#           instructions on where to get the original software distribution.
#
#        d) make other distribution arrangements with the author.
#
#   4. You may modify and include the part of the software into any other
#      software (possibly commercial).  But some files in the distribution
#      are not written by the author, so that they are not under this terms.
#
#      They are gc.c(partly), utils.c(partly), regex.[ch], st.[ch] and some
#      files under the ./missing directory.  See each file for the copying
#      condition.
#
#   5. The scripts and library files supplied as input to or produced as
#      output from the software do not automatically fall under the
#      copyright of the software, but belong to whomever generated them,
#      and may be sold commercially, and may be aggregated with this
#      software.
#
#   6. THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
#      IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
#      WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
#      PURPOSE.

class RDInlineParser

  preclow
    nonassoc EX_LOW
    left QUOTE BAR SLASH BACK_SLASH URL OTHER
         REF_OPEN FOOTNOTE_OPEN FOOTNOTE_CLOSE
    nonassoc EX_HIGH
  prechigh

  token EM_OPEN EM_CLOSE
	CODE_OPEN CODE_CLOSE
	VAR_OPEN VAR_CLOSE
	KBD_OPEN KBD_CLOSE
	INDEX_OPEN INDEX_CLOSE
	REF_OPEN REF_CLOSE
	FOOTNOTE_OPEN FOOTNOTE_CLOSE
	VERB_OPEN VERB_CLOSE
	BAR QUOTE SLASH BACK_SLASH URL OTHER EX_LOW EX_HIGH

  rule
    content : elements
	    ;
    elements : elements element { result.push(val[1]) }
	     | element          { result = val }
	     ;
    element : emphasis
            | code
            | var
            | keyboard
            | index
            | reference
            | footnote
            | verb
	    | normal_str_ele
            ;

    emphasis : EM_OPEN content EM_CLOSE {
		result = Emphasis.new
                add_children_to_element(result, *val[1])
					 }
             ;
    code :     CODE_OPEN content CODE_CLOSE {
		result = Code.new
                add_children_to_element(result, *val[1])
					 }
         ;
    var :      VAR_OPEN content VAR_CLOSE {
		result = Var.new
                add_children_to_element(result, *val[1])
					 }
        ;
    keyboard : KBD_OPEN content KBD_CLOSE {
		result = Keyboard.new
                add_children_to_element(result, *val[1])
					 }
             ;
    index :    INDEX_OPEN content INDEX_CLOSE {
		result = Index.new
                add_children_to_element(result, *val[1])
					 }
          ;

# Refernce
# ((<subst|filename/element_label>))

    reference : REF_OPEN substitute ref_label REF_CLOSE
			{ result = Reference.new(val[2])
                          add_children_to_element(result, *val[1])
        		 }
	      | REF_OPEN ref_label2 REF_CLOSE
                        {
                          result = make_reference_from_label(val[1])
			}
              ;

    ref_label : URL ref_url_strings  { result = Reference::URL.new(val[1]) }
              | filename element_label
	       		{ result = Reference::TemporaryLabel.new(val[1],
			           val[0]) }
              | element_label
			 { result = Reference::TemporaryLabel.new(val[0]) }
	      | filename { result = Reference::TemporaryLabel.new([], val[0]) }
              ;
    ref_label2 : URL ref_url_strings  { result = Reference::URL.new(val[1]) }
	       | filename element_label2
	       		{ result = Reference::TemporaryLabel.new(val[1],
				   val[0]) }
	       | element_label2
			 { result = Reference::TemporaryLabel.new(val[0]) }
 	       | filename { result = Reference::TemporaryLabel.new([],
				     val[0]) }
               ;
    substitute : ref_subst_content BAR
	       | QUOTE ref_subst_content_q QUOTE BAR
				{ result = val[1] }
    	       | QUOTE ref_subst_strings_q QUOTE BAR
				{ result = [StringElement.new(val[1])] }
               ;

    filename : ref_subst_strings_first SLASH
	     | QUOTE ref_subst_strings_q QUOTE SLASH
				{ result = val[1] }
	     ;

    # when substitute part exists
    element_label : ref_subst_strings_first
				{ result = [StringElement.new(val[0])] }
		  | QUOTE ref_subst_strings_q QUOTE
				{ result = [StringElement.new(val[1])] }
		  ;
    # when substitute part doesn't exist
    # in this case, element label can contain Inlines
    element_label2 : ref_subst_content
		   | QUOTE ref_subst_content_q QUOTE
					       { result = val[1] }
		   | QUOTE ref_subst_strings_q QUOTE
				{ result = [StringElement.new(val[1])] }
		   ;

    ref_subst_content : ref_subst_ele2 ref_subst_eles
				       { result = val[1].unshift(val[0]) }
		      | ref_subst_str_ele_first ref_subst_eles
					{ result = val[1].unshift(val[0]) }
		      | ref_subst_str_ele_first
					{ result = val }
		      | ref_subst_ele2  { result = val }
		      ;
    ref_subst_content_q : ref_subst_eles_q
			;
    ref_subst_eles : ref_subst_eles ref_subst_ele
					{ result.push(val[1]) }
		   | ref_subst_ele	{ result = val }
		   ;
    ref_subst_eles_q : ref_subst_eles_q ref_subst_ele_q
					{ result.push(val[1]) }
		     | ref_subst_ele_q  { result = val }
		     ;
    ref_subst_ele2 : emphasis
		   | code
		   | var
		   | keyboard
		   | index
		   | verb
		   ;
    ref_subst_ele : ref_subst_ele2
   		  | ref_subst_str_ele
		  ;
    ref_subst_ele_q : ref_subst_ele2
		    | ref_subst_str_ele_q
		    ;

    ref_subst_str_ele : ref_subst_strings = EX_LOW
				{ result = StringElement.new(val[0]) }
		      ;
    ref_subst_str_ele_first : ref_subst_strings_first
				{ result = StringElement.new(val[0]) }
                        ;
    ref_subst_str_ele_q : ref_subst_strings_q = EX_LOW
				{ result = StringElement.new(val[0]) }
		        ;

    ref_subst_strings : ref_subst_strings ref_subst_string3
					  { result << val[1] }
		      | ref_subst_string3
		      ;
    # if it is first element of substitute, it can't contain
    #  URL on head.
    ref_subst_strings_first : ref_subst_string ref_subst_strings = EX_HIGH
					       { result << val[1] }
			    | ref_subst_string = EX_LOW
			    ;
    ref_subst_strings_q : ref_subst_strings_q ref_subst_string_q
					      { result << val[1] }
			| ref_subst_string_q
			;

    ref_subst_string : OTHER
		     | BACK_SLASH
		     | REF_OPEN
		     | FOOTNOTE_OPEN
		     | FOOTNOTE_CLOSE
		     ;
    ref_subst_string2 : ref_subst_string
 		      | URL
		      ;
    ref_subst_string3 : ref_subst_string2
		      | QUOTE
		      ;
    ref_subst_string_q : ref_subst_string2
		       | BAR
		       | SLASH
		       ;
# end subst

# string in url
     ref_url_strings : ref_url_strings ref_url_string { result << val[1] }
		       | ref_url_string
		       ;

     ref_url_string : OTHER
		      | BACK_SLASH BACK_SLASH
 		      | URL
                      | SLASH
                      | BAR
                      | QUOTE
		      | EM_OPEN
		      | EM_CLOSE
		      | CODE_OPEN
		      | CODE_CLOSE
		      | VAR_OPEN
		      | VAR_CLOSE
		      | KBD_OPEN
		      | KBD_CLOSE
		      | INDEX_OPEN
		      | INDEX_CLOSE
		      | REF_OPEN
		      | FOOTNOTE_OPEN
		      | FOOTNOTE_CLOSE
		      | VERB_OPEN
		      | VERB_CLOSE
		      ;

# end url
# end Reference

    footnote : FOOTNOTE_OPEN content FOOTNOTE_CLOSE {
		result = Footnote.new
                add_children_to_element(result, *val[1])
					 }
             ;
    verb :     VERB_OPEN verb_strings VERB_CLOSE {
				result = Verb.new(val[1]) }
         ;


    # normal string
    # OTHER, QUOTE, BAR, SLASH, BACK_SLASH, URL
    normal_string : OTHER
		  | QUOTE
		  | BAR
		  | SLASH
		  | BACK_SLASH
		  | URL
		  ;
    normal_strings : normal_strings normal_string
				      { result << val[1] }

		   | normal_string
		   ;
    normal_str_ele : normal_strings = EX_LOW
				    { result = StringElement.new(val[0]) }
		   ;

    # in verb
    verb_string : verb_normal_string
		| BACK_SLASH verb_normal_string { result = val[1] }
		| BACK_SLASH VERB_CLOSE { result = val[1] }
		| BACK_SLASH BACK_SLASH { result = val[1] }
		;

    verb_normal_string : OTHER
		| QUOTE
		| BAR
		| SLASH
		| EM_OPEN
		| EM_CLOSE
		| CODE_OPEN
		| CODE_CLOSE
		| VAR_OPEN
		| VAR_CLOSE
		| KBD_OPEN
		| KBD_CLOSE
		| INDEX_OPEN
		| INDEX_CLOSE
		| REF_OPEN
		| REF_CLOSE
		| FOOTNOTE_OPEN
		| FOOTNOTE_CLOSE
		| VERB_OPEN
		| URL
		;

    verb_strings : verb_strings verb_string { result << val[1] }
		 | verb_string
		 ;
/*    verb_str_ele : verb_strings
		 ; */
end

---- inner
include ParserUtility
extend Forwardable

EM_OPEN = '((*'
EM_OPEN_RE = /\A#{Regexp.quote(EM_OPEN)}/
EM_CLOSE = '*))'
EM_CLOSE_RE = /\A#{Regexp.quote(EM_CLOSE)}/
CODE_OPEN = '(({'
CODE_OPEN_RE = /\A#{Regexp.quote(CODE_OPEN)}/
CODE_CLOSE = '}))'
CODE_CLOSE_RE = /\A#{Regexp.quote(CODE_CLOSE)}/
VAR_OPEN = '((|'
VAR_OPEN_RE = /\A#{Regexp.quote(VAR_OPEN)}/
VAR_CLOSE = '|))'
VAR_CLOSE_RE = /\A#{Regexp.quote(VAR_CLOSE)}/
KBD_OPEN = '((%'
KBD_OPEN_RE = /\A#{Regexp.quote(KBD_OPEN)}/
KBD_CLOSE = '%))'
KBD_CLOSE_RE = /\A#{Regexp.quote(KBD_CLOSE)}/
INDEX_OPEN = '((:'
INDEX_OPEN_RE = /\A#{Regexp.quote(INDEX_OPEN)}/
INDEX_CLOSE = ':))'
INDEX_CLOSE_RE = /\A#{Regexp.quote(INDEX_CLOSE)}/
REF_OPEN = '((<'
REF_OPEN_RE = /\A#{Regexp.quote(REF_OPEN)}/
REF_CLOSE = '>))'
REF_CLOSE_RE = /\A#{Regexp.quote(REF_CLOSE)}/
FOOTNOTE_OPEN = '((-'
FOOTNOTE_OPEN_RE = /\A#{Regexp.quote(FOOTNOTE_OPEN)}/
FOOTNOTE_CLOSE = '-))'
FOOTNOTE_CLOSE_RE = /\A#{Regexp.quote(FOOTNOTE_CLOSE)}/
VERB_OPEN = "(('"
VERB_OPEN_RE = /\A#{Regexp.quote(VERB_OPEN)}/
VERB_CLOSE = "'))"
VERB_CLOSE_RE = /\A#{Regexp.quote(VERB_CLOSE)}/

BAR = "|"
BAR_RE = /\A#{Regexp.quote(BAR)}/
QUOTE = '"'
QUOTE_RE = /\A#{Regexp.quote(QUOTE)}/
SLASH = "/"
SLASH_RE = /\A#{Regexp.quote(SLASH)}/
BACK_SLASH = "\\"
BACK_SLASH_RE = /\A#{Regexp.quote(BACK_SLASH)}/
URL = "URL:"
URL_RE = /\A#{Regexp.quote(URL)}/

# Workaround for Regexp option change of Ruby 1.5.x
other_re_mode = Regexp::EXTENDED
if RUBY_VERSION > "1.5"
  other_re_mode |= Regexp::MULTILINE
else
  other_re_mode |= Regexp::POSIXLINE
end

OTHER_RE = Regexp.new(
		  "\\A.+?(?=#{Regexp.quote(EM_OPEN)}|#{Regexp.quote(EM_CLOSE)}|
                  #{Regexp.quote(CODE_OPEN)}|#{Regexp.quote(CODE_CLOSE)}|
                  #{Regexp.quote(VAR_OPEN)}|#{Regexp.quote(VAR_CLOSE)}|
                  #{Regexp.quote(KBD_OPEN)}|#{Regexp.quote(KBD_CLOSE)}|
                  #{Regexp.quote(INDEX_OPEN)}|#{Regexp.quote(INDEX_CLOSE)}|
                  #{Regexp.quote(REF_OPEN)}|#{Regexp.quote(REF_CLOSE)}|
                #{Regexp.quote(FOOTNOTE_OPEN)}|#{Regexp.quote(FOOTNOTE_CLOSE)}|
                  #{Regexp.quote(VERB_OPEN)}|#{Regexp.quote(VERB_CLOSE)}|
                  #{Regexp.quote(BAR)}|
                  #{Regexp.quote(QUOTE)}|
                  #{Regexp.quote(SLASH)}|
                  #{Regexp.quote(BACK_SLASH)}|
                  #{Regexp.quote(URL)})", other_re_mode)

def initialize(bp)
  @blockp = bp
end

def_delegator(:@blockp, :tree)

def parse(src)
  @src = StringScanner.new(src)
  @pre = ""
  @yydebug = true
  do_parse
end

def next_token
  return [false, false] if @src.eos?
#  p @src.rest if @yydebug
  if ret = @src.scan(EM_OPEN_RE)
    @pre << ret
    [:EM_OPEN, ret]
  elsif ret = @src.scan(EM_CLOSE_RE)
    @pre << ret
    [:EM_CLOSE, ret]
  elsif ret = @src.scan(CODE_OPEN_RE)
    @pre << ret
    [:CODE_OPEN, ret]
  elsif ret = @src.scan(CODE_CLOSE_RE)
    @pre << ret
    [:CODE_CLOSE, ret]
  elsif ret = @src.scan(VAR_OPEN_RE)
    @pre << ret
    [:VAR_OPEN, ret]
  elsif ret = @src.scan(VAR_CLOSE_RE)
    @pre << ret
    [:VAR_CLOSE, ret]
  elsif ret = @src.scan(KBD_OPEN_RE)
    @pre << ret
    [:KBD_OPEN, ret]
  elsif ret = @src.scan(KBD_CLOSE_RE)
    @pre << ret
    [:KBD_CLOSE, ret]
  elsif ret = @src.scan(INDEX_OPEN_RE)
    @pre << ret
    [:INDEX_OPEN, ret]
  elsif ret = @src.scan(INDEX_CLOSE_RE)
    @pre << ret
    [:INDEX_CLOSE, ret]
  elsif ret = @src.scan(REF_OPEN_RE)
    @pre << ret
    [:REF_OPEN, ret]
  elsif ret = @src.scan(REF_CLOSE_RE)
    @pre << ret
    [:REF_CLOSE, ret]
  elsif ret = @src.scan(FOOTNOTE_OPEN_RE)
    @pre << ret
    [:FOOTNOTE_OPEN, ret]
  elsif ret = @src.scan(FOOTNOTE_CLOSE_RE)
    @pre << ret
    [:FOOTNOTE_CLOSE, ret]
  elsif ret = @src.scan(VERB_OPEN_RE)
    @pre << ret
    [:VERB_OPEN, ret]
  elsif ret = @src.scan(VERB_CLOSE_RE)
    @pre << ret
    [:VERB_CLOSE, ret]
  elsif ret = @src.scan(BAR_RE)
    @pre << ret
    [:BAR, ret]
  elsif ret = @src.scan(QUOTE_RE)
    @pre << ret
    [:QUOTE, ret]
  elsif ret = @src.scan(SLASH_RE)
    @pre << ret
    [:SLASH, ret]
  elsif ret = @src.scan(BACK_SLASH_RE)
    @pre << ret
    [:BACK_SLASH, ret]
  elsif ret = @src.scan(URL_RE)
    @pre << ret
    [:URL, ret]
  elsif ret = @src.scan(OTHER_RE)
    @pre << ret
    [:OTHER, ret]
  else
    ret = @src.rest
    @pre << ret
    @src.terminate
    [:OTHER, ret]
  end
end

def make_reference_from_label(label)
#  Reference.new_from_label_under_document_struct(label, tree.document_struct)
  Reference.new_from_label_without_document_struct(label)
end

def on_error(et, ev, values)
  lines_of_rest = (RUBY_VERSION >= '1.9.0' ? @src.rest.lines.to_a.length : @src.rest.to_a.length )
  prev_words = prev_words_on_error(ev)
  at = 4 + prev_words.length
  message = <<-MSG
RD syntax error: line #{@blockp.line_index - lines_of_rest}:
...#{prev_words} #{(ev||'')} #{next_words_on_error()} ...
  MSG
  message << " " * at + "^" * (ev ? ev.length : 0) + "\n"
  raise ParseError, message
end

def prev_words_on_error(ev)
  pre = @pre
  if ev and /#{Regexp.quote(ev)}$/ =~ pre
    pre = $`
  end
  last_line(pre)
end

def last_line(src)
  if n = src.rindex("\n")
    src[(n+1) .. -1]
  else
    src
  end
end
private :last_line

def next_words_on_error
  if n = @src.rest.index("\n")
    @src.rest[0 .. (n-1)]
  else
    @src.rest
  end
end

---- header

require "rd/parser-util"
require "forwardable"
require "strscan"

module RD
---- footer
end # end of module RD

