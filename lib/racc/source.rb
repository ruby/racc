# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of LGPL, see the file "COPYING".

module Racc
  module Source
    NL           = /\n|\r\n|\r/
    TAB_WIDTH    = 8
    TAB_TO_SPACE = (' ' * TAB_WIDTH).freeze

    # methods which can be used on any object which represents source text
    module Text
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

      def spiffy(indent = 0)
        cooked = text
        indent = ' ' * indent
        # convert leading tabs to spaces so we get indentation right
        cooked.gsub!(/^ *(\t+)/) { TAB_TO_SPACE * $1.size }
        cooked = (' ' * column) << cooked if column > 0
        cooked.gsub(/^ {#{min_indent}}/, indent)
      end
    end

    class Buffer
      include Text

      def initialize(name, text)
        @name = name
        @text = text
      end

      attr_reader :name
      attr_reader :text

      # for source text which didn't come from a file
      def self.from_string(str)
        new('(string)', str)
      end

      def lineno
        1
      end

      def column
        0
      end

      # `from` is inclusive, `to` is exclusive
      def slice(from, to)
        Buffer.new(name, text[from...to])
      end

      if Array.method_defined?(:bsearch)
        def line_for(offset)
          line, _ = line_offsets.bsearch { |lineno, start| start <= offset }
          line
        end
        def column_for(offset)
          _, column = line_offsets.bsearch { |lineno, start| start <= offset }
          offset - column
        end
      else
        def line_for(offset)
          line, _ = line_offsets.find { |lineno, start| start <= offset }
          line
        end
        def column_for(offset)
          _, column = line_offsets.find { |lineno, start| start <= offset }
          offset - column
        end
      end

      # line N starts at...
      # (a newline is part of the preceding line)
      def line_offsets
        @line_offsets ||= begin
          offsets = [[1, 0]]
          index   = 1
          text.scan(NL) { offsets.unshift([index += 1, $~.end(0)]) }
          offsets
        end
      end

      def min_indent
        lines = text.lines
        lines.map { |line| line[/\A\s*/].gsub("\t", TAB_TO_SPACE).size }.min
      end
    end

    class Range
      include Text

      def initialize(buffer, from, to)
        @buffer = buffer
        @from   = from
        @to     = to
      end

      attr_reader :from
      attr_reader :to

      def text
        @text ||= @buffer.text[@from...@to]
      end

      def name
        @buffer.name
      end

      def lineno
        @buffer.line_for(@from)
      end

      def column
        @buffer.column_for(@from)
      end

      def slice(from, to)
        raise 'slice end must be >= start' if from > to
        max  = @to - @from
        to   = max if to > max
        from = max if from > max
        Range.new(@buffer, @from + from, @from + to)
      end

      def min_indent
        lines  = text.lines
        widths = lines.map { |line| line[/\A\s*/].gsub("\t", TAB_TO_SPACE).size }
        widths[0] += @buffer.column_for(@from)
        widths.min
      end
    end
  end
end
