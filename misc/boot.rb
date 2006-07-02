# $Id$

require 'racc'
require 'stringio'

module Racc

  class State   # reopen
    undef sr_conflict
    def sr_conflict(*args)
      raise 'Racc boot script fatal: S/R conflict in build'
    end

    undef rr_conflict
    def rr_conflict(*args)
      raise 'Racc boot script fatal: R/R conflict in build'
    end
  end


  class BootstrapCompiler

    def BootstrapCompiler.new_generator(states)
      generator = Racc::CodeGenerator.new(states)
      generator.filename = __FILE__
      generator.omit_action_call = true
      generator.result_var = true
      generator.convert_line = true
      generator
    end

    def BootstrapCompiler.main
      states = new().compile
      File.foreach(ARGV[0]) do |line|
        if /STATE_TRANSITION_TABLE/ =~ line
          generator = new_generator(states)
          generator.debug_parser = ARGV.delete('-g')
          generator.parser_table $stdout
        else
          print line
        end
      end
      File.open("#{__FILE__}.output", 'w') {|f|
        Racc::LogFileGenerator.new(states).output f
      }
    end

    # called from lib/racc/pre-setup
    def BootstrapCompiler.generate(template_file)
      states = new().compile
      File.read(template_file).sub(/STATE_TRANSITION_TABLE/) {
        generator = new_generator(states)
        out = StringIO.new
        generator.parser_table out
        out.string
      }
    end

    def compile
      @grammar = Grammar.new
      @symboltable = @grammar.symboltable
      define_grammar
      states = States.init(@grammar)
      states.determine
      states
    end

    private

    def _(rulestr, actstr)
      target, symlist = *parse_rule_exp(rulestr)
      lineno = caller(1)[0].split(':')[1].to_i + 1
      symlist.push UserAction.new(format_action(actstr), lineno)
      @grammar.add target, symlist
    end

    def parse_rule_exp(str)
      tokens = str.strip.scan(/[\:\|]|'.'|\w+/)
      target = (tokens[0] == '|') ? nil : @symboltable.get(tokens.shift.intern)
      tokens.shift   # discard ':' or '|'
      return target,
             tokens.map {|t|
               @symboltable.get(if /\A'/ =~ t
                                then eval(%Q<"#{t[1..-2]}">)
                                else t.intern
                                end)
             }
    end

    def format_action(str)
      str.sub(/\A */, '').sub(/\s+\z/, '')\
          .map {|line| line.sub(/\A {20}/, '') }.join('')
    end

    def define_grammar

_"  xclass      : XCLASS class params XRULE rules opt_end                ", ''

_"  class       : rubyconst                                              ",
                   %{
                        @result.classname = val[0]
                    }
_"              | rubyconst '<' rubyconst                                ",
                   %{
                        @result.classname = val[0]
                        @result.superclass = val[2]
                    }

_"  rubyconst   : XSYMBOL                                                ",
                   %{
                        result = result.id2name
                    }
_"              | rubyconst ':'':' XSYMBOL                               ",
                   %{
                        result << '::' << val[3].id2name
                    }

_"  params      :                                                        ", ''
_"              | params param_seg                                       ", ''

_"  param_seg   : XCONV convdefs XEND                                    ",
                   %{
                        @symboltable.end_register_conv
                    }
_"              | xprec                                                  ", ''
_"              | XSTART symbol                                          ",
                   %{
                        @grammar.start_symbol = val[1]
                    }
_"              | XTOKEN symbol_list                                     ",
                   %{
                        val[1].each do |sym|
                          @symboltable.declare_terminal sym
                        end
                    }
_"              | XOPTION bare_symlist                                   ",
                   %q{
                        val[1].each do |opt|
                          case opt
                          when 'result_var'
                            @result.result_var = true
                          when 'no_result_var'
                            @result.result_var = false
                          when 'omit_action_call'
                            @result.omit_action_call = true
                          when 'no_omit_action_call'
                            @result.omit_action_call = false
                          else
                            raise CompileError, "unknown option: #{opt}"
                          end
                        end
                    }
_"              | XEXPECT DIGIT                                          ",
                   %{
                        if @result.expect
                          raise CompileError, "`expect' seen twice"
                        end
                        @result.expect = val[1]
                    }

_"  convdefs    : symbol STRING                                          ",
                   %{
                        @symboltable.register_conv val[0], val[1]
                    }
_"              | convdefs symbol STRING                                 ",
                   %{
                        @symboltable.register_conv val[1], val[2]
                    }

_"  xprec       : XPRECHIGH preclines XPRECLOW                           ",
                   %{
                        @symboltable.end_register_prec true
                    }
_"              | XPRECLOW preclines XPRECHIGH                           ",
                   %{
                        @symboltable.end_register_prec false
                    }

_"  preclines   : precline                                               ", ''
_"              | preclines precline                                     ", ''

_"  precline    : XLEFT symbol_list                                      ",
                   %{
                        @symboltable.register_prec :Left, val[1]
                    }
_"              | XRIGHT symbol_list                                     ",
                   %{
                        @symboltable.register_prec :Right, val[1]
                    }
_"              | XNONASSOC symbol_list                                  ",
                   %{
                        @symboltable.register_prec :Nonassoc, val[1]
                    }

_"  symbol_list : symbol                                                 ",
                   %{
                        result = val
                    }
_"              | symbol_list symbol                                     ",
                   %{
                        result.push val[1]
                    }
_"              | symbol_list '|'                                        ", ''

_"  symbol      : XSYMBOL                                                ",
                   %{
                        result = @symboltable.get(result)
                    }
_"              | STRING                                                 ",
                   %{
                        result = @symboltable.get(eval(%Q<"\#{result}">))
                    }

_"  rules       : rules_core                                             ",
                   %{
                        add_rule_block result  unless result.empty?
                    }
_"              |                                                        ", ''

_"  rules_core  : symbol                                                 ",
                   %{
                        result = val
                    }
_"              | rules_core rule_item                                   ",
                   %{
                        result.push val[1]
                    }
_"              | rules_core ';'                                         ",
                   %{
                        add_rule_block result  unless result.empty?
                        result.clear
                    }
_"              | rules_core ':'                                         ",
                   %{
                        pre = result.pop
                        add_rule_block result  unless result.empty?
                        result = [pre]
                    }

_"  rule_item   : symbol                                                 ", ''
_"              | '|'                                                    ",
                   %{
                        result = OrMark.new(@scanner.lineno)
                    }
_"              | '=' symbol                                             ",
                   %{
                        result = Prec.new(val[1], @scanner.lineno)
                    }
_"              | ACTION                                                 ",
                   %{
                        result = UserAction.new(*result)
                    }

_"  bare_symlist: XSYMBOL                                                ",
                   %{
                        result = [ result.id2name ]
                    }
_"              | bare_symlist XSYMBOL                                   ",
                   %{
                        result.push val[1].id2name
                    }

_"  opt_end     : XEND                                                   ", ''
_"              |                                                        ", ''

    end

  end

end   # module Racc

if $0 == __FILE__
  Racc::BootstrapCompiler.main
end
