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

    def light_purple(text)
      "\e[1;35m#{text}\e[0m"
    end

    def light_green(text)
      "\e[1;32m#{text}\e[0m"
    end

    def yellow(text)
      "\e[1;33m#{text}\e[0m"
    end
  end
end