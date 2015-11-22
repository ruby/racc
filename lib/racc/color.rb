module Racc
  # Support module for printing colored text to an ANSI terminal
  module Color
    @color_enabled = false

    def self.enabled=(enabled)
      @color_enabled = enabled
    end

    def self.enabled?
      @color_enabled
    end

    def red(text)
      return text unless Color.enabled?
      "\e[31m#{text}\e[0m"
    end

    def green(text)
      return text unless Color.enabled?
      "\e[32m#{text}\e[0m"
    end

    def bold_white(text)
      return text unless Color.enabled?
      "\e[1;37m#{text}\e[0m"
    end

    # nonterminals are light purple
    def nonterminal(name)
      "\e[1;35m#{name}\e[0m"
    end

    # terminals are light green
    def terminal(name)
      "\e[1;32m#{name}\e[0m"
    end

    def symbol(sym)
      return sym.to_s unless Color.enabled?
      if sym.terminal?
        terminal(sym.to_s)
      else
        nonterminal(sym.to_s)
      end
    end
  end
end