
  class RaccParser < Parser

    attr :start
    attr :classname


    def initialize( racc )
      racc.must Racc
      @racc   = racc
      @interf = racc.interf

      @scanner = RaccScanner.new
      @scanner.debug = @yydebug = $RACCPARSER_DEBUG
    end


    def parse( str, fname )
      fname.must String
      @scanner.reset( str )
      @scanner.filename = @filename = fname

      do_parse
    end

    def next_token
      @scanner.scan
    end

    def on_error( tok, val, state, sstack, vstack )
      raise ParseError, <<MES
  parse error:#{@filename}:#{@scanner.lineno}: unexpected token '#{val}'
MES
    end

