# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".

module Racc
  class LogFileGenerator
    def initialize(states, debug_flags = DebugFlags.new)
      @states = states
      @grammar = states.grammar
      @debug_flags = debug_flags
    end

    def output(out)
      output_conflict out; out.puts
      output_useless  out; out.puts
      output_rule     out; out.puts
      output_token    out; out.puts
      output_state    out
    end

    #
    # Warnings
    #

    def output_conflict(out)
      @states.each do |state|
        if state.sr_conflicts.any?
          out.printf "state %d contains %d shift/reduce conflicts\n",
                     state.ident, state.sr_conflicts.size
        end
        if state.rr_conflicts.any?
          out.printf "state %d contains %d reduce/reduce conflicts\n",
                     state.ident, state.rr_conflicts.size
        end
      end
    end

    def output_useless(out)
      @grammar.symboltable.nonterminals.select(&:useless?).each do |t|
        out.printf "useless nonterminal %s\n", t.to_s
      end
    end

    # States

    def output_state(out)
      out << "--------- State ---------\n"

      showall = @debug_flags.la || @debug_flags.state
      @states.each do |state|
        out << "\nstate #{state.ident}\n\n"

        (showall ? state.closure : state.core).each do |ptr|
          pointer_out(out, ptr) if ptr.rule.ident != 0 or showall
        end
        out << "\n"

        action_out out, state
      end
    end

    def pointer_out(out, ptr)
      buf = sprintf("%4d) %s :", ptr.rule.ident, ptr.rule.target.to_s)
      ptr.rule.symbols.each_with_index do |tok, idx|
        buf << ' _' if idx == ptr.index
        buf << ' ' << tok.to_s
      end
      buf << ' _' if ptr.reduce?
      out.puts buf
    end

    def action_out(f, state)
      sr = state.sr_conflicts
      rr = state.rr_conflicts
      tokens = state.action.keys.sort_by(&:ident)

      [Shift, Reduce, Error, Accept].each do |klass|
        tokens.each do |tok|
          act = state.action[tok]
          if act.kind_of?(klass)
            outact(f, tok, act)
            outsrconf(f, sr[tok]) if sr.key?(tok)
            outrrconf(f, rr[tok]) if rr.key?(tok)
          end
        end
      end

      sr.each { |tok, c| outsrconf(f, c) if state.action[tok].nil? }
      rr.each { |tok, c| outrrconf(f, c) if state.action[tok].nil? }

      if !state.defact.kind_of?(Error) || @debug_flags.any?
        outact(f, '$default', state.defact)
      end

      f.puts
      state.gotos.each do |tok, goto|
        if tok.nonterminal?
          next_state = goto.to_state
          f.printf("  %-12s  go to state %d\n", tok.to_s, next_state.ident)
        end
      end
    end

    def outact(f, t, act)
      case act
      when Shift
        f.printf "  %-12s  shift, and go to state %d\n",
                 t.to_s, act.goto_state.ident
      when Reduce
        f.printf "  %-12s  reduce using rule %d (%s)\n",
                 t.to_s, act.rule.ident, act.rule.target.to_s
      when Accept
        f.printf "  %-12s  accept\n", t.to_s
      when Error
        f.printf "  %-12s  error\n", t.to_s
      else
        raise "racc: fatal: wrong act for outact: act=#{act}(#{act.class})"
      end
    end

    def outsrconf(f, conf)
      r = conf.reduce
      f.printf("  %-12s  [reduce using rule %d (%s)]\n",
               conf.shift.to_s, r.ident, r.target.to_s)
    end

    def outrrconf(f, conf)
      r = conf.low_prec
      f.printf("  %-12s  [reduce using rule %d (%s)]\n",
               conf.token.to_s, r.ident, r.target.to_s)
    end

    #
    # Rules
    #

    def output_rule(out)
      out.print "-------- Grammar --------\n\n"
      @grammar.each do |rl|
        if @debug_flags.any? or rl.ident != 0
          out.printf "rule %d %s: %s\n",
                     rl.ident, rl.target.to_s, rl.symbols.join(' ')
        end
      end
    end

    #
    # Tokens
    #

    def output_token(out)
      out.print "------- Symbols -------\n\n"

      out.print "**Nonterminals, with rules where they appear\n\n"
      @grammar.symboltable.nonterminals.each do |t|
        tmp = <<SRC
  %s (%d)
    on right: %s
    on left : %s
SRC
        out.printf tmp, t.to_s, t.ident,
                   symbol_locations(t.locate).join(' '),
                   symbol_locations(t.heads).join(' ')
      end

      out.print "\n**Terminals, with rules where they appear\n\n"
      @grammar.symboltable.terminals.each do |t|
        out.printf "  %s (%d) %s\n",
                   t.to_s, t.ident, symbol_locations(t.locate).join(' ')
      end
    end

    def symbol_locations(locs)
      locs.map {|loc| loc.rule.ident }.reject {|n| n == 0 }.uniq
    end
  end
end
