#
# register.rb
#
#   Copyright (c) 1999,2000 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#
#   This program is free software.
#   You can distribute/modify this program under the terms of
#   the GNU Lesser General Public License version 2 or later.
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
      @racc       = racc
      @ruletable  = racc.ruletable
      @tokentable = racc.tokentable
      
      @precs = []
      @emb = 1
      @tmpprec = nil
      @token_list = nil

      @end_rule = false
      @end_conv = false
      @end_prec = false
    end

    
    def get_symbol( val )
      @tokentable.get( val )
    end


    def register_from_array( arr )
      sym = arr.shift
      case sym
      when OrMark, Action, Prec
        raise ParseError, "#{sym.lineno}: unexpected token #{sym.name}"
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
    

    def embed_symbol( act )
      sim = get_symbol( "@#{@emb}".intern )
      @emb += 1
      @ruletable.register sim, [], nil, act

      sim
    end

    def register_rule( symbol, list )
      if symbol then
        @pre = symbol
      else
        symbol = @pre
      end

      if Action === list[-1] then
        act = list.pop
      else
        act = Action.new( '', 0 )
      end
      list.collect! do |t|
        Action === t ? embed_symbol( t ) : t
      end

      @ruletable.register symbol, list, @tmpprec, act
      @ruletable.start = symbol
      @tmpprec = nil
    end

    def end_register_rule
      @end_rule = true
      if @ruletable.size == 0 then
        raise RaccError, 'rules not exist'
      end

      @ruletable.token_list = @token_list if @token_list
    end

    def register_tmpprec( prec )
      if @tmpprec then
        raise ParseError, "'=<prec>' used twice in one rule"
      end
      @tmpprec = prec
    end


    def register_prec( atr, toks )
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
        raise ParseError, "'convert' block is defined twice"
      end

      tok.conv = str
    end

    def end_register_conv
      @end_conv = true
    end


    def register_token( list )
      @token_list ||= []
      @token_list.concat list
    end


    def register_start( tok )
      unless @ruletable.start = tok then
        raise ParseError, "'start' defined twice'"
      end
    end


    def register_option( option )
      if m = /\Ano_/.match(option) then
        opt = m.post_match
        flg = true
      else
        opt = option
        flg = false
      end
      case opt
      when 'omit_action_call'
        @racc.omit_action = inv(flg, true)
      when 'result_var'
        @racc.result_var = inv(flg, true)
      else
        raise ParseError, "unknown option '#{option}'"
      end
    end
    
    def inv( i, f )
      if i then !f else f end
    end

  end   # BuildInterface

end   # module Racc
