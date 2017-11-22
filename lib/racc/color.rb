module Racc
  # Support module for printing colored text to an ANSI terminal
  module Color
    extend self
    @color_enabled = false

    def self.enabled=(enabled)
      @color_enabled = enabled
    end

    def self.enabled?
      @color_enabled
    end

    def self.without_color
      saved = @color_enabled
      @color_enabled = false
      yield
    ensure
      @color_enabled = saved
    end

    def bright(text)
      return text unless Color.enabled?
      text = text.gsub(/\e\[.*?m[^\e]*\e\[0m/, "\e[0m\\0\e[1m")
      String.new "\e[1m#{text}\e[0m"
    end

    def red(text)
      return text unless Color.enabled?
      String.new "\e[31m#{text}\e[0m"
    end

    def green(text)
      return text unless Color.enabled?
      String.new "\e[32m#{text}\e[0m"
    end

    def violet(text)
      return text unless Color.enabled?
      String.new "\e[1;35m#{text}\e[0m"
    end

    # Syntax highlighting for various types of symbols...
    def nonterminal(text)
      return text unless Color.enabled?
      String.new "\e[1;34m#{text}\e[0m" # blue
    end

    def terminal(text)
      return text unless Color.enabled?
      String.new "\e[1;36m\e[4m#{text}\e[0m" # cyan, with underline
    end

    def string(text)
      return text unless Color.enabled?
      String.new "\e[1;33m#{text}\e[0m" # bright yellow
    end

    def explicit_prec(text)
      return text unless Color.enabled?
      String.new "\e[1;31m#{text}\e[0m" # bright reddish orange
    end
  end
end
