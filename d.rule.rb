
  class BuildInterface

    def initialize( rac )
      @ruletable = rac.ruletable
      @tokentable = @ruletable.tokentable

      @precs = []

      @end_rule = false
      @end_conv = false
      @end_prec = false
    end

    
    def get_token( val )
      @tokentable.get_token( val )
    end
    
    def register_rule( simbol, rulearr, tempprec, actstr )
      @d_rule and
        puts "register: add: #{simbol} -> #{rulearr.join(' ')}"

      @end_rule and
        raise ParseError, "'rule' block is defined twice"

      if simbol then
        @pre = simbol
      else
        simbol = @pre
      end
      unless actstr then actstr = '' end

      @ruletable.register( simbol, rulearr, tempprec, actstr )
    end

    def end_register_rule
      @end_rule = true
    end


    def register_prec( atr, toks )
      @d_prec and
        puts "register: atr=#{atr.id2name}, toks=#{toks.join(' ')}"

      @end_prec and
        raise ParseError, "'prec' block is defined twice"

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
      @end_conv and
        raise ParseError, "'token' block is defined twice"

      tok.conv = str
    end

    def end_register_conv
      @end_conv = true
    end

  end
    

  class RuleTable

    attr :tokentable


    def initialize( rac )
      @racc     = rac

      @d_token = rac.d_token
      @d_rule  = rac.d_rule
      @d_state = rac.d_state

      @tokentable = TokenTable.new

      @rules    = []
      @finished = false
      @hashval  = 4
    end


    def register( simbol, rulearr, tempprec, actstr )
      rule = Rule.new(
        simbol, rulearr, actstr,
        @rules.size + 1,         # ID
        @hashval,                # hash
        tempprec                 # prec
      )
      @rules.push rule

      @hashval += (rulearr.size + 2)
    end
   
    
    def do_initialize( start )

      ### add dammy rule

      start  = (start or @rules[0].simbol)
      dammy  = @tokentable.get_token( Parser::Dammy )
      anchor = @tokentable.get_token( Parser::Anchor )

      temp = Rule.new(
        dammy, [ start, anchor ], '',
        0,     # id
        0,     # hash
        nil    # prec token
      )
      @rules.unshift temp
      @rules.freeze


      ### cache

      @rules.each do |rule|
        rule.simbol.rules.push rule.ptrs(0)
      end

      @tokentable.each_token do |tok|
        tok.term = (tok.rules.size == 0)
      end

      @tokentable.each_token do |tok|
        tok.first
      end

      @rules.each do |rule|
        temp = nil

        rule.each_ptr do |ptr|
          tok = ptr.unref
          tok.locate.push ptr
          if tok.term then temp = tok end
        end

        (rule.prec = temp) unless rule.prec
      end
    end


    def []( x ) @rules[x] end

    def each_rule ( &data ) @rules.each( &data ) end

    def to_s() "<Racc::RuleTable>" end


    def closure( ptrs )
      ptrs = orig_ptrs.uniq
      puts "closure: start: ptrs #{ptrs.join(' ')}" if @d_state

      temp = {}
      ptrs.each do |ptr|
        temp.store( ptr, true )

        tok = ptr.unref
        ptr.reduce? or tok.term or temp.update( tok.expand )
      end
      ret = temp.keys
      ret.sort!{|a,b| a.hash <=> b.hash }

      puts "closure: ret #{ret.join(' ')}" if @d_state
      return ret
    end

  end   # class RuleTable



  class Rule

    attr :action
    attr :simbol
    attr :ruleid
    attr :hashval
    attr :prec, true


    def []( idx ) @rulearr[idx] end

    def size ; @rulearr.size ; end

    def ptrs( idx ) @ptrs[idx] end

    def toks( idx ) @rulearr[idx] end

    def to_s() "<Rule:ID #{@ruleid}>" end

    def ==( other )
      (other.type == Rule) and (@ruleid == other.ruleid)
    end

    def hash() @hashval end

    def accept?()
      (tok = @rulearr[-1]) and tok.anchor?
    end

    def each_token( &data ) @rulearr.each( &data ) end

    def each_ptr( &data )
      pmax = @ptrs.size - 1
      pidx = 0
      while pidx < pmax do
        data.call @ptrs[ pidx ] ; pidx += 1
      end
    end

    def initialize( tok, rlarr, actstr, rid, hval, tprec )
      @simbol  = tok
      @rulearr = rlarr
      @action  = actstr
      @ruleid  = rid
      @hashval = hval
      @prec    = tprec

      @ptrs = []
      rlarr.each_index do |idx|
        @ptrs[ idx ] = RulePointer.new( self, idx, rlarr[idx] )
      end

      # reduce pos
      s = rlarr.size
      @ptrs[ s ] = RulePointer.new( self, s, nil )
    end

  end   # class Rule



  class RulePointer

    attr :rule
    attr :ruleid
    attr :index
    attr :unref
    attr :data


    def initialize( rl, idx, tok )
      @rule   = rl
      @ruleid = rl.ruleid
      @index  = idx
      @unref  = tok

      @hashval = @rule.hash + @index
      @reduce  = tok.nil?
    end


    def to_s
      str = "(#{@rule.ruleid},#{@index}"
      if reduce? then
        str << '#)'
      else
        str << unref.to_s << ')'
      end
      return str
    end

    def inspect
      bug! 'ptr.inspect call'
    end

    def hash()     @hashval end
    def ==( ot )   @hashval == ot.hash end
    def eql?( ot ) @hashval == ot.hash end

    def reduce?()  @unref.nil? end
    def head?()    @index == 0 end

    def increment()
      (ret = @rule.ptrs(@index + 1)) or ptr_bug!
      return ret
    end

    def decrement()
      (ret = @rule.ptrs(@index - 1)) or ptr_bug!
      return ret
    end

    private
    
    def ptr_bug!
      bug! "pointer not exist: self: #{to_s}"
    end

  end   # class RulePointer



  class TokenTable

    def initialize
      @tokens  = {}

      # add system token data
      get_token( Parser::Default )
      get_token( Parser::Anchor )
      get_token( Parser::Dammy )
    end

    def get_token( val )

      ### for same value, Token exist only one

      unless (ret = @tokens.fetch( val )) then
        ret = Token.new( val )
        @tokens.store( val, ret )
      end

      return ret
    end

    def each_token( &data ) @tokens.each_value( &data ) end
    
  end   # class TokenTable



  class Token

    attr     :value
    attr     :rules
    attr     :locate
    attr     :term,                true
    attr     :nullp,               true
    attr     :assoc,               true
    attr     :prec,                true
    property :conv,  String, true, true


    Dammy   = Parser::Dammy
    Anchor  = Parser::Anchor
    Default = Parser::Default


    def initialize( tok )
      if tok.type == Token then tok = tok.value end
      @value = tok

      @valtype = @value.type
      @dammy   = (@value == Dammy)
      @anchor  = (@value == Anchor)
      @hashval = @value.hash

      @rules  = []
      @locate = []
      @term   = nil
      @first  = nil
      @conv   = nil
      @nullp  = nil
      @bfrom  = nil
    end


    def dammy?()  @dammy   end

    def anchor?() @anchor  end

    def hash()    @hashval end

    def to_s
      if    @value  ==  Dammy   then '$dammy'
      elsif Integer === @value  then @value.id2name
      elsif String  === @value  then @value.inspect
      elsif @value  ==  Anchor  then '$end'
      elsif @value  ==  Default then '$default'
      else
        bug! "token#uneval not match: val=#{@value}(#{@value.type})"
      end
    end
    alias inspect to_s


    def uneval
      if    @value  ==  Dammy   then 'Dammy'
      elsif Integer === @value  then ':' << @value.id2name
      elsif String  === @value  then @value.inspect
      elsif @value  ==  Anchor  then 'Anchor'
      elsif @value  ==  Default then 'Default'
      else
        bug! "token#uneval not match: val=#{@value}(#{@value.type})"
      end
    end


    def first
      @d_token and
        puts "get_first: start: token=#{self.to_s}"

      @first and return @first
      @first = {}

      ret = {}
      @nullp = false

      if @term then
        ret.store( self, true )
      else
        temp = {}
        @rules.each do |ptr|
          if ptr.reduce? then
            # reduce --> index 0 is null
            @nullp = true
          else
            temp.store( ptr.unref, true )
          end
        end

        temp.each_key do |tok|
          ret.update tok.first
        end
      end

      @first = ret
      @d_token and
        puts "get_first: for #{token}, ret #{ret.keys.join(' ')}"

      return ret
    end


    def expand
      @d_state and
        puts "expand: start: tok=#{self.to_s}"

      @bfrom and return @bfrom
      @bfrom = {}

      ret  = {}
      temp = {}
      @rules.each do |ptr|
        ret.store( ptr, true )
        tok = ptr.unref
        if not ptr.reduce? and not tok.term then
          temp.store( tok, true )
        end
      end
      temp.each_key do |tok|
        ret.update tok.expand
      end

      @bfrom = ret
      @d_state and
        puts "expand: ret #{ret.keys.join(' ')}"

      return ret
    end

  end   # Token

