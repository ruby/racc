
  class RaccParser < Parser

    attr :start
    attr :classname


    def initialize( rac )
      @racc   = (rac.must Racc)
      @interf = @racc.interf

      @scanner = RaccScanner.new

      @scanner.debug = @yydebug = $RACCPARSER_DEBUG
    end


    def parse( str, fname )
      @scanner.reset( str )
      @sbuf = @scanner.spipe
      @vbuf = @scanner.vpipe

      @filename = (fname.must String)
      @scanner.filename = @filename

      do_parse
    end

    def next_token
      if @sbuf.size == 0 then @scanner.scan end
      @sbuf.shift
    end

    def next_value
      if @vbuf.size == 0 then @scanner.scan end
      @vbuf.shift
    end

    def peep_token
      if @sbuf.size == 0 then @scanner.scan end
      @sbuf[0]
    end

    def on_error( tok, val, state, sstack, vstack )
      raise ParseError, <<MES
  parse error:#{@filename}:#{@scanner.lineno}: unexpected token '#{val}'
MES
    end

