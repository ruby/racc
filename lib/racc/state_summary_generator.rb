require 'racc/state'
require 'racc/directed_graph'
require 'racc/util'

require 'erb'

module Racc
  class StateSummaryGenerator
    def initialize(states, filename)
      @states   = states
      @filename = filename
    end

    def generate_summary_file(destpath)
      if destpath == '-'
        puts render
      else
        File.open(destpath, 'w') do |f|
          f.write(render)
        end
      end
    end

    def render
      ERB.new(TEMPLATE, nil, nil, '@output').result(binding)
    end

    private

    def print_state_title(state)
      @output << "State #{state.ident}"
      @output << ' (end state)' if state.defact.is_a?(Accept)
      @output << ' (start state)' if state.ident == 0
    end

    def print_loc_ptr_as_tr(ptr)
      rule = ptr.rule

      @output << '<tr><td>'
      print_symbol(rule.target)
      @output << '</td><td><b>:</b></td><td>'
      if ptr.index > 0
        rule.symbols[0...ptr.index].reject(&:hidden).each do |sym|
          print_symbol(sym)
          @output << ' '
        end
      end
      @output << '<b>.</b> '
      unless ptr.reduce?
        rule.symbols[ptr.index..-1].reject(&:hidden).each do |sym|
          print_symbol(sym)
          @output << ' '
        end
      end
      if sym = rule.explicit_precedence
        print_explicit_prec(sym)
      end
      @output << '</td></tr>'
    end

    def print_rule(rule)
      print_symbol(rule.target)
      @output << ' <b>:</b>'
      print_symbols(rule.symbols)
      if sym = rule.explicit_precedence
        @output << ' '
        print_explicit_prec(sym)
      end
    end

    def print_overridden_rule(rule, action)
      @output << "<br/>(<span style='color: red'>Overridden:</span> "
      @output << action << ' by '
      print_rule(rule)
      @output << ')'
    end

    def print_overridden_rules(rules, action)
      rules.each { |rule| print_overridden_rule(rule, action) }
    end

    def print_symbols(syms)
      syms.each do |sym|
        next if sym.hidden
        @output << ' '
        print_symbol(sym)
      end
    end

    def print_symbol(sym)
      if sym.string_symbol?
        @output << "<span style='color: #A4A017; font-weight: bold'>" \
          "#{sym.display_name}" \
          "</span>"
      elsif sym.terminal?
        @output << "<span style='color: #239449; text-decoration: underline'>" \
          "#{sym.display_name}" \
          "</span>"
      else
        @output << "<span style='color: #36318D'>" \
          "#{sym.display_name}" \
          "</span>"
      end
    end

    def print_explicit_prec(sym)
      @output << "<span style='color: red; font-weight: bold'>" \
        "=#{sym.display_name}" \
        "</span>"
    end

    def print_shortest_path(state)
      stack = []
      @output << '<thead><tr><th><b>Action:</b></th><th><b>Stack:</b></th></tr></thead>'
      @output << '<tbody>'
      state.shortest_detailed_path.each do |step|
        if step.is_a?(Sym)
          stack << step
          @output << '<tr><td>Shift '
          print_symbol(step)
          @output << '</td><td>'
          print_symbols(stack)
          @output << '</td></tr>'
        else
          rhs     = step.rule.symbols.reject(&:hidden)
          reduced = rhs.size.times.map { stack.pop }.reverse
          stack << step.symbol

          @output << '<tr><td>Reduce to '
          print_symbol(step.symbol)
          @output << ' by:<br/>'
          print_rule(step.rule)
          @output << '</td><td>'
          print_symbols(stack)
          @output << '</td></tr>'
        end
      end
      @output << '</tbody>'
    end

    def print_action_table(state)
      @output << '<thead><tr><th><b>Lookahead token</b></th><th><b>Action</b></th></tr></thead>'
      @output << '<tbody>'
      state.action.sort_by { |k,v| k.ident }.each do |tok, act|
        @output << '<tr><td>'
        print_symbol(tok)
        @output << '</td><td>'
        print_action(state, tok, act)
        @output << '</td></tr>'
      end
      if state.defact
        @output << '<tr><td>Other</td><td>'
        print_action(state, nil, state.defact)
        @output << '</td></tr>'
      end
      @output << '</tbody>'
    end

    def print_action(state, token, action)
      if action.is_a?(Reduce)
        @output << 'Reduce by '
        print_rule(action.rule)
        @output << '<br/>'
        print_state_links(@states.possible_reduce_destinations(state, action.rule))
        if sr = state.sr_conflicts[token]
          print_overridden_rules(sr.srules, 'shift')
        end
        if rr = state.rr_conflicts[token]
          print_overridden_rules(rr.rules.drop(1), 'reduce')
        end
      elsif action.is_a?(Shift)
        n = action.goto_state.ident
        @output << "Shift and go to state <a href='\#state#{n}'>#{n}</a>"
        if rr = state.rr_conflicts[token]
          print_overridden_rules(rr.rules, 'reduce')
        elsif sr = state.sr_conflicts[token]
          print_overridden_rule(sr.rrule, 'reduce')
        end
      elsif action.is_a?(Accept)
        @output << 'Accept (success!)'
      elsif action.is_a?(Error)
        @output << 'Error'
      end
    end

    def print_action_phrase(action)
      if action.is_a?(Reduce)
        @output << 'reduce by '
        print_rule(action.rule)
      elsif action.is_a?(Shift)
        @output << "shift and go to state #{action.goto_state.ident}"
      elsif action.is_a?(Accept)
        @output << 'stop parsing and return success'
      elsif action.is_a?(Error)
        @output << 'throw an error'
      end
    end

    def print_state_links(states)
      @output << (states.one? ? '(This takes us to ' : '(This can take us to ')
      states = states.map { |s| "<a href='\#state#{s.ident}'>#{s.ident}</a>" }
      @output << Racc.to_sentence(states, 'or')
      @output << ')'
    end

    TEMPLATE = <<-END
<!DOCTYPE html>
<html>
  <head>
    <title>LR parser states for <%= @filename %></title>
    <style type='text/css'>
      table           { border-collapse: collapse }
      th, td          { padding: 0.25rem; text-align: left; border: 1px solid #ccc; }

      table.core td   { border: none }
      table.core tr   { border: 1px solid #ccc }
      table.path      { border: 2px solid #ccc }
      table.action    { border: 2px solid #ccc }
    </style>
  </head>
  <body>
    <!-- details for each state -->
    <% @states.each do |state| %>
      <h2><a name="state<%= state.ident %>"><% print_state_title(state) %></a></h2>

      <p><table class='core'>
        <%
        state.core.each do |ptr|
          print_loc_ptr_as_tr(ptr)
        end
        %>
      </table></p>

      <% unless state.shortest_detailed_path.empty? %><p>
        This state can be reached from the start state by:<br/>
        <table class='path'><% print_shortest_path(state) %></table>
      </p><% end %>

      <p>
      <% if state.action.empty? %>
        From here, we <% print_action_phrase(state.defact) %> regardless of what token
        comes next.<br/>
        <% if state.defact.is_a?(Reduce) %>
          <% print_state_links(@states.possible_reduce_destinations(state, state.defact.rule)) %>
        <% end %>
      <% else %>
        Action table:<br/>
        <table class='action'><% print_action_table(state) %></table>
      <% end %>
      </p>
      <hr>
    <% end %>
    <!-- indexes -->
  </body>
</html>
    END
  end
end