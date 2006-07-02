module Racc

  GenerationOptions = Struct.new(:debug_parser,
                                 :omit_action_call,
                                 :result_var,
                                 :convert_line,
                                 :filename,
                                 :lineno_base,

                                 # For Racc command
                                 :convert_line_all,
                                 :classname,
                                 :superclass,
                                 :make_executable,
                                 :interpreter,
                                 :embed_runtime,
                                 :runtime)
  class GenerationOptions   # reopen
    def initialize
      self.debug_parser = false
      self.omit_action_call = true
      self.result_var = true
      self.convert_line = true
      self.filename = nil
      self.lineno_base = 0

      self.convert_line_all = false
      self.classname = nil
      self.superclass = nil
      self.make_executable = false
      self.interpreter = nil
      self.embed_runtime = false
      self.runtime = nil
    end

    alias debug_parser?         debug_parser
    alias omit_action_call?     omit_action_call
    alias result_var?           result_var
    alias convert_line?         convert_line
    alias convert_line_all?     convert_line_all
    alias make_executable?      make_executable
    alias embed_runtime?        embed_runtime

    private

    def bool(x)
      x ? true : false
    end
  end

  class DebugFlags
    def DebugFlags.parse_option_string(s)
      parse = rule = token = state = la = prec = conf = false
      s.split(//).each do |ch|
        case ch
        when 'p' then parse = true
        when 'r' then rule = true
        when 't' then token = true
        when 's' then state = true
        when 'l' then la = true
        when 'c' then prec = true
        when 'o' then conf = true
        else
          raise "unknown debug flag char: #{ch.inspect}"
        end
      end
      new(parse, rule, token, state, la, prec, conf)
    end

    def initialize(parse = false, rule = false, token = false, state = false, la = false, prec = false, conf = false)
      @parse = parse
      @rule = rule
      @token = token
      @state = state
      @la = la
      @prec = prec
      @any = (parse || rule || token || state || la || prec)
      @status_logging = conf
    end

    attr_reader :parse
    attr_reader :rule
    attr_reader :token
    attr_reader :state
    attr_reader :la
    attr_reader :prec

    def any?
      @any
    end

    attr_reader :status_logging
  end

end
