%%machine lex;

require 'ripper'
require 'racc/exception'
require 'racc/source'

class Racc::GrammarFileScanner
  ReservedWords = {
    'right'    => :RIGHT,
    'left'     => :LEFT,
    'nonassoc' => :NONASSOC,
    'preclow'  => :PRECLOW,
    'prechigh' => :PRECHIGH,
    'token'    => :TOKEN,
    'convert'  => :CONV,
    'options'  => :OPTION,
    'start'    => :START,
    'expect'   => :EXPECT,
    'class'    => :CLASS,
    'rule'     => :RULE,
    'end'      => :END
  }

  Delimiters = {
    '{' => '}',
    '<' => '>',
    '[' => ']',
    '(' => ')'
  }

  attr_accessor :file
  attr_accessor :lineno
  attr_accessor :epilogue

  def initialize(file)
    @file     = file
    @source   = file.text.force_encoding(Encoding::ASCII_8BIT)
    @eof      = @source.length
    @lineno   = 1
    @linehead = true  # are we at the beginning of a line?
    @in_block = false # are we in a 'rule' or 'convert' block?
    @epilogue = ''

    # To make the parser generator output exactly match the legacy generator,
    # collapse excess trailing newlines into just one
    @source.sub!(/\n+\Z/, "\n")

    # Used by Ragel-generated code:
    @data = @source.bytes.to_a

    %%write data;
  end

  def yylex(&block)
    %%write init;
    eof  = @eof
    %%write exec;
    yield nil
  end

  def tok_src
    @source[@ts...@te]
  end

  def token(type = nil, value = nil)
    src_text  = tok_src
    next_line = @lineno + src_text.scan(/\n|\r\n|\r/).size
    type    ||= src_text
    value   ||= block_given? ? yield(src_text) : src_text
    result    = [type, [value, @lineno..next_line]]
    @lineno   = next_line
    result
  end

  def scan_error!(message)
    raise "Error in grammar: #{message}"
  end

  %%{
    access @;
    getkey (@data[p]);

    c_nl       = '\n' | '\r\n' | '\r';
    c_space    = [ \t\r\f\v];
    c_space_nl = c_space | c_nl;

    c_eof      = 0x04 | 0x1a | 0 | zlen;
    c_eol      = c_nl | c_eof;
    c_any      = any - c_eof;

    c_nl_zlen  = c_nl | zlen;
    c_line     = any - c_nl_zlen;

    c_unicode  = c_any - 0x00..0x7f;
    c_upper    = [A-Z];
    c_lower    = [a-z_]  | c_unicode;
    c_alpha    = c_lower | c_upper;
    c_alnum    = c_alpha | [0-9];

    ws_space     = (c_space | '\\' c_nl)+;
    ws_rbcomment = '#' c_line*;
    ws_ccomment  = '/*' (^'*' | '*' ^'/')* '*/';

    ws      = ws_space | ws_rbcomment | ws_ccomment;
    symbol  = /[a-zA-Z_][a-zA-Z0-9_]*/;
    integer = digit+;
    string  = ("'" (^("'" | '\\') | '\\' c_any)* "'") |
              ('"' (^('"' | '\\') | '\\' c_any)* '"');

    #==========================
    # main grammar file scanner
    #==========================

    main := |*
      ws   => { @lineno += @source[@ts...@te].scan(/\n|\r\n|\r/).size };
      c_nl => { @lineno += 1; @linehead = true };

      # start of user code sections
      '----' => {
        yield token(:END, :end) if @in_block # pretend block was closed properly
        @epilogue = @source[@ts...@eof]      # save the remainder of the file
        fbreak;                              # return from yylex
      };

      symbol => {
        symbol_src = tok_src
        if @linehead    # reserved words are only meaningful at line head
          if @in_block  # in rule/convert block, 'end' is the only special word
            if symbol_src == 'end'
              yield token(:END, :end)
              @in_block = false
            else
              yield token(:SYMBOL, &:to_sym)
            end
          elsif symbol_src == 'rule' || symbol_src == 'convert'
            yield token(ReservedWords[symbol_src]) { @in_block = symbol_src.to_sym }
          else
            yield token(ReservedWords.fetch(symbol_src, :SYMBOL), &:to_sym)
          end
        else
          yield token(:SYMBOL, &:to_sym)
        end
        @linehead = false
      };

      integer => {
        yield token(:DIGIT, &:to_i)
        @linehead = false
      };
      string  => {
        yield token(:STRING) { |str_content| eval(str_content) }
        @linehead = false
      };

      '{' => {
        # an action block can only occur inside rule block
        if @in_block == :rule
          rl = RubyLexer.new(@source, p + 1)
          yield token(:ACTION, Racc::Source::Text.new(rl.code, @file.name, @lineno))
          @lineno += rl.code.scan(/\n|\r\n|\r/).size
          fexec rl.position + 1; # jump past the concluding '}'
        else
          yield token
        end
      };

      c_any => {
        @linehead = false if tok_src == '|'
        yield token
      };
    *|;
  }%%

  class RubyLexer < Ripper
    def initialize(src, position)
      super(src[position..-1])

      @source = src
      @start  = @position = position
      @nesting = 0

      catch(:please_stop) { parse }

      while @position < @source.length && @source[@position] =~ /\s/
        @position += 1
      end
      @code = @source[@start...@position]

      if @source[@position] != '}'
        # TODO: more detailed diagnostics
        raise Racc::ScanError, "scan error in action block"
      end
    end

    attr_reader :position, :code

    (SCANNER_EVENTS - [:embexpr_beg, :embexpr_end, :lbrace, :rbrace]).each do |event|
      class_eval("def on_#{event}(tok); @position += tok.bytesize; end")
    end

    # On Ruby 2.0+, Ripper emits an embexpr_end token for the concluding }
    # On Ruby 1.9, it's an rbrace
    def on_embexpr_beg(tok)
      @nesting  += 1
      @position += tok.size
    end

    def on_lbrace(tok)
      @nesting  += 1
      @position += tok.size
    end

    def on_embexpr_end(tok)
      @nesting -= 1
      throw :please_stop if @nesting < 0
      @position += tok.size
    end

    def on_rbrace(tok)
      @nesting -= 1
      throw :please_stop if @nesting < 0
      @position += tok.size
    end
  end
end