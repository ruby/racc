#
# parser.rb
#
#   Copyright (c) 1999,2000 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#
#   This program is free software.
#   You can distribute/modify this program under the terms of
#   the GNU Lesser General Public License version 2 or later.
#
#   As a special exception, when this code is copied by Racc
#   into a Racc output file, you may use that output file
#   without restriction.
#

module Racc
  class ParseError < StandardError; end
end
unless defined? ParseError then
  ParseError = Racc::ParseError
end


module Racc

  class Parser

    private


    begin
      require 'racc/cparse'   # def _c_parse
      Racc_Main_Parsing_Routine = :_c_parse
    rescue LoadError
      Racc_Main_Parsing_Routine = :_rb_parse
    end


    def next_token
      raise NotImplementError, "#{self.type}#next_token must be defined"
    end


    def do_parse
      t = self.type
      unless t::Racc_debug_parser then
        @yydebug = false
      end
      @yydebug = @yydebug ? true : false
      if @yydebug then
        @racc_debug_out ||= $stderr
      end

      send Racc_Main_Parsing_Routine, t::Racc_arg, true
    end


    def _rb_parse( arg, in_debug )
      action_table, action_check, action_default, action_pointer,
      goto_table, goto_check, goto_default, goto_pointer,
      nt_base, reduce_table, token_table, shift_n, reduce_n,
      use_result = *arg
      if use_result.nil? then
        use_result = arg[-1] = true
      end

      #
      # local variables
      #

      state    = [ 0 ]
      curstate = 0

      tstack = []
      vstack = []

      atmp = tok = val = t = nil
      act = tmp = code = i = nil
      read_next = true

      @racc_error_status = 0
      nerr = 0
      user_yyerror = false

      t_end = 0    # $end
      t_err = 1    # error token

      yydebug = @yydebug

      #
      # LR parsing algorithm main loop
      #

      while true do

        if i = action_pointer[ curstate ] then
          if read_next then
            if t != t_end then
              atmp = next_token
              tok = atmp[0]
              val = atmp[1]
              t = (token_table[tok] or t_err)
              racc_read_token( t, tok, val ) if yydebug

              read_next = false
            end
          end
          i += t
          if i >= 0 and act = action_table[i] and
             action_check[i] == curstate then
          else
            act = action_default[ curstate ]
          end
        else
          act = action_default[ curstate ]
        end

    begin
        if act > 0 and act < shift_n then
          #
          # shift
          #

          if @racc_error_status > 0 then
            @racc_error_status -= 1
          end

          vstack.push val
          if yydebug then
            tstack.push t
            racc_shift( t, tstack, vstack )
          end

          curstate = act
          state.push curstate

          read_next = true

        elsif act < 0 and act > -reduce_n then
          #
          # reduce
          #

          code = catch( :racc_jump ) {
            curstate = racc_do_reduce( arg, state, vstack, tstack, act )
            state.push curstate; false
          }
          if code then
            case code
            when 1 # yyerror
              act = -reduce_n
              user_yyerror = true
              redo
            when 2 # yyaccept
              act = shift_n
              redo
            else
              raise RuntimeError, '[Racc Bug] unknown jump code'
            end
          end

        elsif act == shift_n then
          #
          # accept
          #

          racc_accept if yydebug
          return vstack[0]

        elsif act == -reduce_n then
          #
          # error
          #

          case @racc_error_status
          when 0
            unless user_yyerror then
              nerr += 1
              on_error( t, val, vstack )
            end
          when 3
            if t == t_end then
              return nil
            end
            read_next = true
          end
          user_yyerror = false
          @racc_error_status = 3

          while true do
            if i = action_pointer[curstate] then
              i += t_err
              if i >= 0 and
                 (act = action_table[i]) and
                 action_check[i] == curstate then
                break
              end
            end

            return nil if state.size < 2
            state.pop
            vstack.pop
            if yydebug then
              tstack.pop
              racc_e_pop( state, tstack, vstack )
            end
            curstate = state[-1]
          end

          if act > 0 and act < shift_n then
            #
            # error-shift
            #
            vstack.push val
            if yydebug then
              tstack.push t_err
              racc_shift( t_err, tstack, vstack )
            end

            curstate = act
            state.push curstate
            
          elsif act < 0 and act > -reduce_n then
            #
            # error-reduce
            #
            code = catch( :racc_jump ) {
              curstate = racc_do_reduce( arg, state, vstack, tstack, act )
              state.push curstate; 0
            }
            unless code == 0 then
              case code
              when 1 # yyerror
                act = -reduce_n
                user_yyerror = true
                redo
              when 2 # yyaccept
                act = shift_n
                redo
              else
                raise RuntimeError, '[Racc Bug] unknown jump code'
              end
            end

          elsif act == shift_n then
            #
            # error-accept
            #
            racc_accept if yydebug
            return vstack[0]

          else
            raise RuntimeError, "[Racc Bug] wrong act value #{act.inspect}"
          end

        else
          raise RuntimeError, "[Racc Bug] unknown action #{act.inspect}"
        end
    end while false

        racc_next_state( curstate, state ) if yydebug
      end

      raise RuntimeError, '[Racc Bug] must not reach here'
    end


    def on_error( t, val, vstack )
      raise ParseError, "\nunexpected token #{val.inspect}"
    end


    def racc_do_reduce( arg, state, vstack, tstack, act )
      action_table, action_check, action_default, action_pointer,
      goto_table, goto_check, goto_default, goto_pointer,
      nt_base, reduce_table, token_table, shift_n, reduce_n,
      use_result = *arg

      i = act * -3
      len       = reduce_table[i]
      reduce_to = reduce_table[i+1]
      method_id = reduce_table[i+2]
      void_array = []

      tmp_t = tstack[ -len, len ] if @yydebug
      tmp_v = vstack[ -len, len ]
      tstack[ -len, len ] = void_array if @yydebug
      vstack[ -len, len ] = void_array
      state[ -len, len ]  = void_array

      # tstack must be renewed AFTER method call
      if use_result then
        vstack.push send(method_id, tmp_v, vstack, tmp_v[0])
      else
        vstack.push send(method_id, tmp_v, vstack)
      end
      tstack.push reduce_to

      racc_reduce( tmp_t, reduce_to, tstack, vstack ) if @yydebug

      k1 = reduce_to - nt_base
      if i = goto_pointer[ k1 ] then
        i += state[-1]
        if i >= 0 and (curstate = goto_table[i]) and goto_check[i] == k1 then
          return curstate
        end
      end
      goto_default[ k1 ]
    end

    def yyerror
      throw :racc_jump, 1
    end

    def yyaccept
      throw :racc_jump, 2
    end

    def yyerrok
      @racc_error_status = 0
    end


    # for debugging output

    def racc_read_token( t, tok, val )
      @racc_debug_out.print 'read    '
      @racc_debug_out.print tok.inspect, '(internaly ', racc_token2str(t), ') '
      @racc_debug_out.puts val.inspect
      @racc_debug_out.puts
    end

    def racc_shift( tok, tstack, vstack )
      @racc_debug_out.puts "shift   #{racc_token2str tok}"
      racc_print_stacks tstack, vstack
      @racc_debug_out.puts
    end

    def racc_reduce( toks, sim, tstack, vstack )
      out = @racc_debug_out
      out.print 'reduce '
      if toks.empty? then
        out.print ' <none>'
      else
        toks.each {|t| out.print ' ', racc_token2str(t) }
      end
      out.puts " --> #{racc_token2str(sim)}"
          
      racc_print_stacks tstack, vstack
      @racc_debug_out.puts
    end

    def racc_accept
      @racc_debug_out.puts 'accept'
      @racc_debug_out.puts
    end

    def racc_e_pop( state, tstack, vstack )
      @racc_debug_out.puts 'error recovering mode: pop token'
      racc_print_states state
      racc_print_stacks tstack, vstack
      @racc_debug_out.puts
    end

    def racc_next_state( curstate, state )
      @racc_debug_out.puts  "goto    #{curstate}"
      racc_print_states state
      @racc_debug_out.puts
    end

    def racc_print_stacks( t, v )
      out = @racc_debug_out
      out.print '        ['
      t.each_index do |i|
        out.print ' (', racc_token2str(t[i]), ' ', v[i].inspect, ')'
      end
      out.puts ' ]'
    end

    def racc_print_states( s )
      out = @racc_debug_out
      out.print '        ['
      s.each {|st| out.print ' ', st }
      out.puts ' ]'
    end

    def racc_token2str( tok )
      type::Racc_token_to_s_table[tok] or
        raise RuntimeError, "[Racc Bug] can't convert token #{tok} to string"
    end

  end

end
