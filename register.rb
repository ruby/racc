#
# register.rb
#
#   Copyright (c) 1999 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#

module Racc

  class Action
  
    def initialize( str, lineno )
      @val = (/\A\s*\z/ === str ? nil : str)
      @lineno = lineno
    end

    attr :val
    attr :lineno

    def name
      '{action}'
    end
    alias inspect name
  
  end

  class OrMark

    def initialize( lineno )
      @lineno = lineno
    end

    def name
      '|'
    end
    alias inspect name

    attr :lineno

  end

  class Prec
  
    def initialize( tok, lineno )
      @val = tok
      @lineno = lineno
    end

    def name
      '='
    end
    alias inspect name

    attr :val
    attr :lineno
  
  end


  class BuildInterface

    def initialize( racc )
      @ruletable  = racc.ruletable
      @tokentable = racc.tokentable
      
      @d_prec = racc.d_prec

      @precs = []
      @emb = 1
      @tmpprec = nil

      @end_rule = false
      @end_conv = false
      @end_prec = false
    end

    
    def get_token( val )
      @tokentable.get( val )
    end


    def register_from_array( arr )
      sym = arr.shift
      case sym
      when OrMark, Action, Prec
        raise ParseError, "line #{sym.lineno}: unexpected token #{sym.name}"
      end
      tmp = []
      arr.each do |i|
        case i
        when OrMark
          register_rule sym, tmp
          tmp = []
        when Prec
          register_tmpprec i.val
        else
          tmp.push i
        end
      end
      register_rule sym, tmp
    end
    

    def embed_simbol( act )
      sim = get_token( "@#{@emb}".intern )
      @emb += 1
      @ruletable.register sim, [], nil, act

      sim
    end

    def register_rule( simbol, list )
      if simbol then
        @pre = simbol
      else
        simbol = @pre
      end

      if Action === list[-1] then
        act = list.pop
      else
        act = Action.new( '', 0 )
      end
      list.filter do |t|
        Action === t ? embed_simbol( t ) : t
      end

      @ruletable.register simbol, list, @tmpprec, act
      @ruletable.start = simbol
      @tmpprec = nil
    end

    def end_register_rule
      @end_rule = true
    end

    def register_tmpprec( prec )
      if @tmpprec then
        raise ParseError, "'=<prec>' used twice in one rule"
      end
      @tmpprec = prec
    end


    def register_prec( atr, toks )
      puts "register: atr=#{atr.id2name}, toks=#{toks.join(' ')}" if @d_prec

      if @end_prec then
        raise ParseError, "'prec' block is defined twice"
      end

      toks.push atr
      @precs.push toks
    end

    def end_register_prec( rev )
      @end_prec = true

      top = @precs.size - 1
      @precs.each_with_index do |toks, idx|
        atr = toks.pop

        toks.each do |tok|
          tok.assoc = atr
          if rev then
            tok.prec = top - idx
          else
            tok.prec = idx
          end
        end
      end
    end


    def register_conv( tok, str )
      if @end_conv then
        raise ParseError, "'token' block is defined twice"
      end

      tok.conv = str
    end

    def end_register_conv
      @end_conv = true
    end


    def register_start( tok )
      unless @ruletable.start = tok then
        raise ParseError, "'start' defined twice'"
      end
    end

  end   # BuildInterface

end   # module Racc
