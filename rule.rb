#
# rule.rb
#
#   Copyright (c) 1999 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#

module Racc

  class RuleTable

    def initialize( rac )
      @racc = rac
      @tokentable = rac.tokentable

      @d_token = rac.d_token
      @d_rule  = rac.d_rule
      @d_state = rac.d_state

      @rules    = []
      @finished = false
      @hashval  = 4
      @start    = nil
    end


    def register( simbol, rulearr, tempprec, act )
      rule = Rule.new(
        simbol, rulearr, act,
        @rules.size + 1,         # ID
        @hashval,                # hash value
        tempprec                 # prec
      )
      @rules.push rule

      @hashval += rulearr.size + 2
    end

    def start=( sim )
      unless @start then
        @start = sim
        true
      else
        false
      end
    end
    
    attr :start


    def init

      ### add dummy rule

      temp = Rule.new(
          @tokentable.dummy,
          [ @start, @tokentable.anchor, @tokentable.anchor ],
          Action.new( '', 0 ),
          0, 0, nil )
        # id hash prec
      @rules.unshift temp
      @rules.freeze


      ### cache

      @rules.each do |rule|
        rule.simbol.rules.push rule.ptrs(0)
      end

      @tokentable.fix

      @rules.each do |rule|
        temp = nil

        rule.each_ptr do |ptr|
          tok = ptr.unref
          tok.locate.push ptr
          temp = tok if tok.term
        end

        rule.prec = temp if rule.prec.nil?
      end
    end


    def []( x )
      @rules[x]
    end

    def each_rule( &block )
      @rules.each( &block )
    end
    alias each each_rule

    def each_index( &block )
      @rules.each_index( &block )
    end

    def each_with_index( &block )
      @rules.each_with_index( &block )
    end

    def size
      @rules.size
    end

    def to_s
      "<Racc::RuleTable>"
    end

  end   # RuleTable



  class Rule

    def initialize( tok, rlarr, act, rid, hval, tprec )
      @simbol  = tok
      @rulearr = rlarr
      @action  = act.val
      @lineno  = act.lineno
      @ruleid  = rid
      @hash    = hval
      @prec    = tprec

      @ptrs = []
      rlarr.each_index do |idx|
        @ptrs[ idx ] = RulePointer.new( self, idx, rlarr[idx] )
      end

      # reduce pos
      s = rlarr.size
      @ptrs[ s ] = RulePointer.new( self, s, nil )
    end


    attr :action
    attr :lineno
    attr :simbol
    attr :ruleid
    attr :hash
    attr :prec, true

    def ==( other )
      Rule === other and @ruleid == other.ruleid
    end

    def accept?()
      if tok = @rulearr[-1] then
        tok.anchor?
      else
        false
      end
    end

    def []( idx )
      @rulearr[idx]
    end

    def size
      @rulearr.size
    end

    def to_s
      "<Rule:ID #{@ruleid}>"
    end

    def ptrs( idx )
      @ptrs[idx]
    end

    def pointers
      @ptrs.dup
    end

    def toks( idx )
      @rulearr[idx]
    end

    def tokens
      @rulearr.dup
    end

    def each_token( &block )
      @rulearr.each( &block )
    end
    alias each each_token

    def each_with_index( &block )
      @rulearr.each_with_index( &block )
    end

    def each_ptr( &block )
      pmax = @ptrs.size - 1
      i = 0
      while i < pmax do
        yield @ptrs[i]
        i += 1
      end
    end

  end   # Rule



  class RulePointer

    attr :rule
    attr :ruleid
    attr :index
    attr :unref
    attr :data
    attr :hash


    def initialize( rl, idx, tok )
      @rule   = rl
      @ruleid = rl.ruleid
      @index  = idx
      @unref  = tok

      @hash   = @rule.hash + @index
      @reduce = tok.nil?
    end


    def to_s
      sprintf( '(%d,%d %s)',
               @rule.ruleid, @index, reduce? ? '#' : unref.to_s )
    end
    alias inspect to_s

    def eql?( ot )
      @hash == ot.hash
    end
    alias == eql?

    def reduce?
      @unref.nil?
    end

    def head?
      @index == 0
    end

    def increment
      ret = @rule.ptrs( @index + 1 )
      ret or ptr_bug!
    end

    def decrement
      ret = @rule.ptrs( @index - 1 )
      ret or ptr_bug!
    end

    def before( len )
      ret = @rule.ptrs( @index - len )
      ret or ptr_bug!
    end

    private
    
    def ptr_bug!
      bug! "pointer not exist: self: #{to_s}"
    end

  end   # class RulePointer



  class TokenTable

    include Enumerable

    def initialize( racc )
      @racc = racc

      @chk = {}
      @tokens = []
      
      @dummy   = get( :$start )
      @anchor  = get( :$end )
      @error   = get( :error )   # error token is ID 1

      @anchor.conv = 'false'
      @error.conv = 'Object.new'
    end

    attr :dummy
    attr :anchor

    def get( val )
      unless ret = @chk[ val ] then
        @chk[ val ] = ret = Token.new( val, @racc )
        @tokens.push ret
      end

      ret
    end

    def fix
      tok = nil
      @tokens.each do |tok|
        tok.term = (tok.rules.size == 0)
      end

      term = []
      nt = []
      i = nil
      @tokens.each do |i|
        (i.terminal? ? term : nt).push i
      end
      @tokens = term
      @nt_base = term.size
      term.concat nt

      @tokens.each_with_index do |t, i|
        t.tokenid = i
      end
    end

    attr :nt_base

    def nt_max
      @tokens.size
    end

    def each( &block )
      @tokens.each &block
    end

    def each_terminal( &block )
      @tokens[ 0, @nt_base ].each( &block )
    end

    def each_nonterm( &block )
      @tokens[ @nt_base, @tokens.size - @nt_base ].each( &block )
    end


    def init
      tok = nil
      @tokens.each {|tok| tok.compute_expand   unless tok.terminal? }
      @tokens.each {|tok| tok.compute_nullable unless tok.terminal? }
      @tokens.each {|tok| tok.compute_first    unless tok.terminal? }
      @tokens.each {|tok| tok.compute_follow   unless tok.terminal? }
    end

  end   # TokenTable


  class Token

    Default_token_id = -1
    Anchor_token_id  = 0
    Error_token_id   = 1

    def initialize( tok, racc )
      @tokenid = nil
      @value   = tok
      @tokenid = nil

      @hash   = @value.hash

      @term   = nil
      @conv   = nil

      @rules  = []
      @locate = []
      @null   = nil
      @expand = nil
      @first  = nil
      @follow = nil

      @d_token = racc.d_token


      # for human
      @to_s = case @value
              when Symbol then @value.id2name
              when String then @value.inspect
              else
                bug! "wrong token value: #{@value}(#{@value.type})"
              end

      # for ruby source
      @uneval = case @value
                when Symbol then ':' + @value.id2name
                when String then @value.inspect
                else
                  bug! "wrong token value: #{@value}(#{@value.type})"
                end
    end

    def tokenid=( tid )
      if @tokenid then
        bug! "token id initialized twice"
      end
      @tokenid = tid
    end

    def conv=( str )
      @conv = @uneval = str
    end


    attr :tokenid

    attr :value
    attr :hash

    attr :term,  true
    attr :conv # true
    attr :prec,  true
    attr :assoc, true

    attr :rules
    attr :locate
    attr :expand
    attr :null
    attr :first
    attr :follow

    alias terminal? term
    alias nullable? null


    def to_s
      @to_s.dup
    end
    alias inspect to_s

    def uneval
      @uneval.dup
    end


    # only on left
    def useless?
      not @terminal and @locate.empty?
    end


    def compute_expand
      puts "expand> #{to_s}" if @d_token
      @expand = upd_expand( {}, [] )
      puts "expand< #{to_s}: #{@expand.keys.join(' ')}" if @d_token
    end

    def upd_expand( ret, lock )
      if @expand then
        ret.update @expand
        return @expand
      end
      lock[tokenid] = true

      nterm = {}
      tok = h = nil

      @rules.each do |ptr|
        ret[ptr] = true
        tok = ptr.unref
        if tok and not tok.terminal? then
          nterm[ tok ] = true
        end
      end
      nterm.each_key do |tok|
        unless lock[tok.tokenid] then
          tok.upd_expand( ret, lock )
        end
      end

      ret
    end


    def compute_nullable
      puts "null?> #{to_s}" if @d_token
      @null = check_null( [] )
      puts "null?< #{to_s}: #{@null}" if @d_token
    end

    def check_null( lock )
      return @null unless @null.nil?
      lock[tokenid] = true

      ptr = tok = nil

      @rules.each do |ptr|
        while true do
          if ptr.reduce? then
            return true
          end
          tok = ptr.unref

          break if tok.terminal?
          break if lock[tok.tokenid]
          break unless tok.check_null( lock )
          ptr = ptr.increment
        end
      end

      false
    end


    def compute_first
      puts "first> #{to_s}" if @d_token
      @first = upd_first( {}, [] )
      puts "first< #{to_s}: #{@first.keys.join(' ')}" if @d_token
    end

    def upd_first( ret, lock )
      if @first then
        ret.update @first
        return @first
      end
      lock[tokenid] = true

      ptr = tok = nil

      if terminal? then
        bug! '"first" called for terminal'
      else
        @rules.each do |ptr|
          until ptr.reduce? do
            tok = ptr.unref
            if tok.terminal? then
              ret[ tok ] = true
              break
            else
              tok.upd_first( ret, lock ) unless lock[tok.tokenid]
              break unless tok.nullable?
            end

            ptr = ptr.increment
          end
        end
      end

      ret
    end


    def compute_follow
      puts "follow> #{to_s}" if @d_token
      @follow = upd_follow( {}, [] )
      puts "follow< #{to_s}: #{@follow.keys.join(' ')}" if @d_token
    end

    def upd_follow( ret, lock )
      if @follow then
        ret.update @follow
        return @follow
      end
      lock[tokenid] = true

      ptr = tok = nil

      @locate.each do |ptr|
        while true do
          ptr = ptr.increment || ptr
          if ptr.reduce? then
            tok = ptr.rule.simbol
            tok.upd_follow( ret, lock ) unless lock[tok.tokenid]
            break
          end
          tok = ptr.unref
          if tok.terminal? then
            ret[tok] = true
            break
          else
            ret.update tok.first
            break unless tok.nullable?
          end
        end
      end

      ret
    end

  end   # class Token

end   # module Racc
