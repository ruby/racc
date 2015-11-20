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

class RDParser

  preclow
    nonassoc DUMMY
    left     ITEMLISTLINE ENUMLISTLINE DESCLISTLINE METHODLISTLINE STRINGLINE
  prechigh

  token STRINGLINE ITEMLISTLINE ENUMLISTLINE DESCLISTLINE METHODLISTLINE
	WHITELINE SUBTREE HEADLINE INCLUDE INDENT DEDENT DUMMY

  rule
  document : blocks  { result = DocumentElement.new
		       add_children_to_element(result, *val[0])
                     }
	     |         {
                         raise ParseError,
                         "Error: file empty."
			  }
             ;
    blocks : blocks block  { result.concat(val[1]) }
           | block
           ;
    block : textblock	  { result = val }
          | verbatim      { result = val }
          | lists
          | headline      { result = val }
          | include       { result = val }
          | WHITELINE     { result = [] }
          | SUBTREE       { result = val[0].blocks }
          ;

    headline : HEADLINE { # val[0] is like [level, title]
			  title = @inline_parser.parse(val[0][1])
			  result = Headline.new(val[0][0])
			  add_children_to_element(result, *title)
                          }
             ;
    include : INCLUDE { result = Include.new(val[0]) }
	    ;

    textblock : textblockcontent = DUMMY
			{ # val[0] is Array of String
			  content = cut_off(val[0]).join("")
			  contents = @inline_parser.parse(content)
			  result = TextBlock.new()
			  add_children_to_element(result, *contents)
                         }
              ;
    textblockcontent : textblockcontent STRINGLINE
				 { result.push(val[1]) }
                     | STRINGLINE { result = val }
                     ;

    verbatim : INDENT verbatimcontent DEDENT
			{ # val[1] is Array of String
			  content = cut_off(val[1])
			  result = Verbatim.new(content)
			  # imform to lexer.
			  @in_verbatim = false }
             ;
    verbatim_after_lists : verbatimcontent
			{ # val[0] is Array of String
			  content = cut_off(val[0])
			  result = Verbatim.new(content)
			  # imform to lexer.
			  @in_verbatim = false }
             ;
    verbatimcontent : verbatimcontent STRINGLINE
					{ result.push(val[1]) }
                    | verbatimcontent INDENT verbatimcontent DEDENT
 					{ result.concat(val[2]) }
                    | verbatimcontent WHITELINE
					{ result.push("\n") }
                    | STRINGLINE      { result = val
					# imform to lexer.
					@in_verbatim = true }
  		    ;

    list : itemlist
         | enumlist
         | desclist
         | methodlist
         ;
    lists : lists2 = DUMMY
	  | INDENT lists2 DEDENT { result = val[1] }
	  | INDENT lists2 verbatim_after_lists DEDENT
		  		{ result = val[1].push(val[2]) }
	  ;

    lists2 : lists2 list { result.push(val[1]) }
	   | list	 { result = val }
	   ;

    itemlist :  itemlistitems  = DUMMY {
                          result = ItemList.new
			  add_children_to_element(result, *val[0])
                           }
	 ;
    itemlistitems : itemlistitems itemlistitem
			{ result.push(val[1]) }
              | itemlistitem { result = val }
              ;
    itemlistitem : first_textblock_in_itemlist other_blocks_in_list DEDENT
		{
                  result = ItemListItem.new
		  add_children_to_element(result, val[0], *val[1])
                 }
                 ;

    enumlist :  enumlistitems  = DUMMY {
                          result = EnumList.new
			  add_children_to_element(result, *val[0])
                           }
	 ;
    enumlistitems : enumlistitems enumlistitem
			{ result.push(val[1]) }
              | enumlistitem { result = val }
              ;
    enumlistitem : first_textblock_in_enumlist other_blocks_in_list DEDENT
		{
                  result = EnumListItem.new
		  add_children_to_element(result, val[0], *val[1])
                 }
                 ;

    desclist : desclistitems  = DUMMY {
                          result = DescList.new
			  add_children_to_element(result, *val[0])
                           }
	 ;
    desclistitems : desclistitems desclistitem {
			result.push(val[1]) }
              | desclistitem { result = val }
              ;
    desclistitem : DESCLISTLINE description_part DEDENT
			{
                          term = DescListItem::Term.new
                          term_contents = @inline_parser.parse(val[0].strip)
			  add_children_to_element(term, *term_contents)

			  result = DescListItem.new
                          set_term_to_element(result, term)
		          add_children_to_element(result, *val[1])
                         }
		 ;

    methodlist : methodlistitems  = DUMMY {
                          result = MethodList.new
			  add_children_to_element(result, *val[0])
                           }
	 ;
    methodlistitems : methodlistitems methodlistitem
			{ result.push(val[1]) }
              | methodlistitem { result = val }
              ;
    methodlistitem : METHODLISTLINE description_part DEDENT
			{
			  term = MethodListItem::Term.new(val[0].strip)
			  result = MethodListItem.new
                          set_term_to_element(result, term)
			  add_children_to_element(result, *val[1])
			 }
		 ;

    description_part : whitelines textblock blocks_in_list
				 { result = [val[1]].concat(val[2]) }
		     | whitelines textblock { result = [val[1]] }
		     | whitelines INDENT blocks_in_list DEDENT
				{ result = val[2] }
		     | whitelines { result = [] }
		     ;

    blocks_in_list : blocks_in_list block_in_list { result.concat(val[1]) }
                   | block_in_list
                   ;
    block_in_list : textblock	    { result = val }
                  | verbatim        { result = val }
                  | lists
                  | WHITELINE       { result = [] }
                  ;
    whitelines  : whitelines2
  		|
		;
    whitelines2 : WHITELINE whitelines2
		| WHITELINE
		;

    first_textblock_in_itemlist : ITEMLISTLINE textblockcontent

		{ content = cut_off([val[0]].concat(val[1])).join("")
		  contents = @inline_parser.parse(content)
                  result = TextBlock.new()
		  add_children_to_element(result, *contents)
                 }
				| ITEMLISTLINE

		{ content = cut_off([val[0]]).join("")
		  contents = @inline_parser.parse(content)
		  result = TextBlock.new()
		  add_children_to_element(result, *contents)
		}
				 ;
    first_textblock_in_enumlist : ENUMLISTLINE textblockcontent

		{ content = cut_off([val[0]].concat(val[1])).join("")
		  contents = @inline_parser.parse(content)
	          result = TextBlock.new()
		  add_children_to_element(result, *contents)
		 }
				 | ENUMLISTLINE

		{ content = cut_off([val[0]]).join("")
		  contents = @inline_parser.parse(content)
	          result = TextBlock.new()
		  add_children_to_element(result, *contents)
		 }
				 ;
    other_blocks_in_list : verbatim blocks_in_list
				    { result = [val[0]].concat(val[1]) }
			 | lists blocks_in_list    { result.concat(val[1]) }
			 | WHITELINE blocks_in_list { result = val[1] }
			 | verbatim { result = val }
			 | lists
			 | WHITELINE { result = [] }
			 | { result = [] }
			 ;
end

---- inner
include ParserUtility

TMPFILE = ["rdtmp", $$, 0]

attr_reader :tree

def initialize
  @inline_parser = RDInlineParser.new(self)
end

def parse(src, tree)
  @src = src
  @src.push(false)
  # RDtree
  @tree = tree

  # @i: index(line no.) of src
  @i = 0
  # stack for current indentation
  @indent_stack = []
  # how indented.
  @current_indent = @indent_stack.join("")
  # RDParser for tmp src
  @subparser = nil
  # which part is in now
  @in_part = nil
  @part_content = []

  @in_verbatim = false

  @yydebug = true
  do_parse
end

def next_token
  # preprocessing
  # if it is not in RD part
  # => method
  while @in_part != "rd"
    line = @src[@i]
    @i += 1 # next line

    case line
    # src end
    when false
      return [false, false]
    # RD part begin
    when /^=begin\s*(?:\bRD\b.*)?\s*$/
      if @in_part # if in non-RD part
	@part_content.push(line)
      else
	@in_part = "rd"
	return [:WHITELINE, "=begin\n"] # <= for textblockand
      end
    # non-RD part begin
    when /^=begin\s+(\w+)/
      part = $1
      if @in_part # if in non-RD part
	@part_content.push(line)
      else
	@in_part = part if @tree.filter[part] # if filter exists
#	p "BEGIN_PART: #{@in_part}" # DEBUG
      end
    # non-RD part end
    when /^=end/
      if @in_part # if in non-RD part
#	p "END_PART: #{@in_part}" # DEBUG
	# make Part-in object
	part = RD::Part.new(@part_content.join(""), @tree, "r")
	@part_content.clear
	# call filter, part_out is output(Part object)
	part_out = @tree.filter[@in_part].call(part)

	if @tree.filter[@in_part].mode == :rd # if output is RD formated
	  subtree = parse_subtree( (RUBY_VERSION >= '1.9.0' ? part_out.lines.to_a : part_out.to_a ) )
	else # if output is target formated
	  basename = TMPFILE.join('.')
	  TMPFILE[-1] += 1
	  tmpfile = open(@tree.tmp_dir + "/" + basename + ".#{@in_part}", "w")
	  tmpfile.print(part_out)
	  tmpfile.close
	  subtree = parse_subtree(["=begin\n", "<<< #{basename}\n", "=end\n"])
	end
	@in_part = nil
	return [:SUBTREE, subtree]
      end
    else
      if @in_part # if in non-RD part
	@part_content.push(line)
      end
    end
  end

  @current_indent = @indent_stack.join("")
  line = @src[@i]
  case line
  when false
    if_current_indent_equal("") do
      [false, false]
    end
  when /^=end/
    if_current_indent_equal("") do
      @in_part = nil
      [:WHITELINE, "=end"] # MUST CHANGE??
    end
  when /^\s*$/
    @i += 1 # next line
    return [:WHITELINE, ':WHITELINE']
  when /^\#/  # comment line
    @i += 1 # next line
    self.next_token()
  when /^(={1,4})(?!=)\s*(?=\S)/, /^(\+{1,2})(?!\+)\s*(?=\S)/
    rest = $'                    # '
    rest.strip!
    mark = $1
    if_current_indent_equal("") do
      return [:HEADLINE, [Headline.mark_to_level(mark), rest]]
    end
  when /^<<<\s*(\S+)/
    file = $1
    if_current_indent_equal("") do
      suffix = file[-3 .. -1]
      if suffix == ".rd" or suffix == ".rb"
	subtree = parse_subtree(get_included(file))
	[:SUBTREE, subtree]
      else
	[:INCLUDE, file]
      end
    end
  when /^(\s*)\*(\s*)/
    rest = $'                   # '
    newIndent = $2
    if_current_indent_equal($1) do
      if @in_verbatim
	[:STRINGLINE, line]
      else
	@indent_stack.push("\s" << newIndent)
	[:ITEMLISTLINE, rest]
      end
    end
  when /^(\s*)(\(\d+\))(\s*)/
    rest = $'                     # '
    mark = $2
    newIndent = $3
    if_current_indent_equal($1) do
      if @in_verbatim
	[:STRINGLINE, line]
      else
	@indent_stack.push("\s" * mark.size << newIndent)
	[:ENUMLISTLINE, rest]
      end
    end
  when /^(\s*):(\s*)/
    rest = $'                    # '
    newIndent = $2
    if_current_indent_equal($1) do
      if @in_verbatim
	[:STRINGLINE, line]
      else
	@indent_stack.push("\s" << $2)
	[:DESCLISTLINE, rest]
      end
    end
  when /^(\s*)---(?!-|\s*$)/
    indent = $1
    rest = $'
    /\s*/ === rest
    term = $'
    new_indent = $&
    if_current_indent_equal(indent) do
      if @in_verbatim
	[:STRINGLINE, line]
      else
	@indent_stack.push("\s\s\s" + new_indent)
	[:METHODLISTLINE, term]
      end
    end
  when /^(\s*)/
    if_current_indent_equal($1) do
      [:STRINGLINE, line]
    end
  else
    raise "[BUG] parsing error may occured."
  end
end

=begin private
  --- RDParser#if_current_indent_equal(indent)
        if (({@current_indent == ((|indent|))})) then yield block, otherwise
        process indentation.
=end
# always @current_indent = @indent_stack.join("")
def if_current_indent_equal(indent)
  indent = indent.sub(/\t/, "\s" * 8)
  if @current_indent == indent
    @i += 1 # next line
    yield
  elsif indent.index(@current_indent) == 0
    @indent_stack.push(indent[@current_indent.size .. -1])
    [:INDENT, ":INDENT"]
  else
    @indent_stack.pop
    [:DEDENT, ":DEDENT"]
  end
end
private :if_current_indent_equal

def cut_off(src)
  ret = []
  whiteline_buf = []
  line = src.shift
  /^\s*/ =~ line
  indent = Regexp.quote($&)
  ret.push($')                 # '
  while line = src.shift
    if /^(\s*)$/ =~ line
      whiteline_buf.push(line)
    elsif /^#{indent}/ =~ line
      unless whiteline_buf.empty?
	ret.concat(whiteline_buf)
	whiteline_buf.clear
      end
      ret.push($')            # '
    else
      raise "[BUG]: probably Parser Error while cutting off.\n"
    end
  end
  ret
end
private :cut_off

def set_term_to_element(parent, term)
#  parent.set_term_under_document_struct(term, @tree.document_struct)
  parent.set_term_without_document_struct(term)
end
private :set_term_to_element

def on_error( et, ev, _values )
  line = @src[@i]
  prv, cur, nxt = format_line_num(@i, @i+1, @i+2)

  raise ParseError, <<Msg

RD syntax error: line #{@i+1}:
  #{prv}  |#{@src[@i-1].chomp}
  #{cur}=>|#{@src[@i].chomp}
  #{nxt}  |#{@src[@i+1].chomp}

Msg
end

def line_index
  @i
end

def parse_subtree(src)
  @subparser = RD::RDParser.new() unless @subparser

  @subparser.parse(src, @tree)
end
private :parse_subtree

def get_included(file)
  included = ""
  @tree.include_path.each do |dir|
    file_name = dir + "/" + file
    if test(?e, file_name)
      included = IO.readlines(file_name)
      break
    end
  end
  included
end
private :get_included

def format_line_num(*args)
  width = args.collect{|i| i.to_s.length }.max
  args.collect{|i| sprintf("%#{width}d", i) }
end
private :format_line_num

---- header
require "rd/rdinlineparser.tab.rb"
require "rd/parser-util"

module RD
---- footer
end # end of module RD
