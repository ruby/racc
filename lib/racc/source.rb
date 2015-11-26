# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of LGPL, see the file "COPYING".

module Racc
  module Source
    NL = /\n|\r\n|\r/

    # methods which can be used on any object which represents source text
    module TextObject
      def drop_leading_blank_lines
        if text =~ /\A(?:[ \t\f\v]*(?:#{NL}))+/
          slice($~.end(0), text.size)
        else
          self
        end
      end

      def location
        "#{name}:#{lineno}"
      end
    end

    class Buffer < Struct.new(:name, :text)
      include TextObject

      # for source text which didn't come from a file
      def self.from_string(str)
        new('(string)', str)
      end

      def lineno
        1
      end

      # `from` is inclusive, `to` is exclusive
      def slice(from, to)
        Buffer.new(name, text[from...to])
      end
    end

    class Text
      include TextObject

      def initialize(text, buffer, lineno)
        @text = text
        @buffer = buffer
        @lineno = lineno
        freeze
      end

      attr_reader :text
      attr_reader :lineno

      def name
        @buffer.name
      end

      def slice(from, to)
        line = (from == 0) ? @lineno : @lineno + @text[0...from].scan(NL).size
        Text.new(@text[from...to], @buffer, line)
      end
    end
  end
end
