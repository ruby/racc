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
    TERM_WIDTH   = 80

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

      # display with color highlights...
      def spiffy
        highlights.sort_by!(&:from)

        raw    = text
        cooked = String.new
        offset = 0

        highlights.each do |hilite|
          cooked << raw[offset...hilite.from]
          cooked << hilite.to_s
          offset = hilite.to
        end
        cooked << raw[offset...raw.size]
      end

      # ...and with corrected indention...
      def spiffier
        cooked = spiffy
        # convert leading tabs to spaces so we get indentation right
        cooked.gsub!(/^ *(\t+)/) { TAB_TO_SPACE * $1.size }
        cooked = (' ' * column) << cooked if column > 0
        cooked.gsub!(/^ {#{min_indent}}/, '')
        cooked
      end

      # ...and with location
      def spifferific
        loc = location << ': '
        # add extra indentation at every line start EXCEPT the first
        # (to make everything line up)
        cooked = spiffier
        cooked.gsub!(/(?<!\A)^/, ' ' * loc.length)
        "#{Color.bright(loc)}#{cooked}"
      end
    end

    class Buffer
      include Text

      def initialize(name, text)
        @name = name
        @text = text
        @highlights = []
      end

      attr_reader :name, :text
      attr_accessor :highlights

      # for source text which didn't come from a file
      def self.from_string(str)
        new('(string)', str)
      end

      def lineno
        1
      end

      def lines
        1..line_offsets[0][0]
      end

      def column
        0
      end

      # `from` is inclusive, `to` is exclusive
      def slice(from, to)
        Range.new(self, from, to).tap do |range|
          range.highlights =
            @highlights
              .select { |h| h.from >= from && t.to <= to }
              .map { |h| Highlight.new(h.object, h.from - from, h.to - from ) }
        end
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
        @min_indent ||= begin
          lines = text.lines.reject { |line| line =~ /\A\s*\Z/ }
          lines.map { |line| line[/\A\s*/].gsub("\t", TAB_TO_SPACE).size }.min || 0
        end
      end
    end

    class Range
      include Text

      def initialize(buffer, from, to)
        @buffer = buffer
        @from   = from
        @to     = to
        @highlights = []
      end

      attr_reader :from, :to
      attr_accessor :highlights

      def text
        @text ||= @buffer.text[@from...@to]
      end

      def name
        @buffer.name
      end

      def lineno
        @buffer.line_for(@from)
      end

      def lines
        (@buffer.line_for(@from))..(@buffer.line_for(@to))
      end

      def column
        @buffer.column_for(@from)
      end

      def slice(from, to)
        raise 'slice end must be >= start' if from > to
        max  = @to - @from
        to   = max if to > max
        from = max if from > max
        Range.new(@buffer, @from + from, @from + to).tap do |range|
          range.highlights =
            @highlights
              .select { |h| h.from >= from && h.to <= to }
              .map { |h| Highlight.new(h.object, h.from - from, h.to - from) }
        end
      end

      def min_indent
        @min_indent ||= begin
          lines  = text.lines.reject { |line| line =~ /\A\s*\Z/ }
          widths = lines.map { |line| line[/\A\s*/].gsub("\t", TAB_TO_SPACE).size }
          widths[0] += @buffer.column_for(@from)
          widths.min || 0
        end
      end
    end

    class Highlight
      def initialize(object, from, to)
        @object = object # model object which this text represents
        @from   = from   # offset WITHIN parent Buffer/Range
        @to     = to
        freeze
      end

      attr_reader :from, :to, :object

      def to_s
        object.to_s # code objects print themselves with color highlighting
      end
    end

    # A (sparse) set of lines from a Buffer or Range
    class SparseLines
      def initialize(textobj, line_ranges)
        @textobj = textobj
        @lines   = line_ranges.sort_by(&:begin)
        freeze
      end

      attr_reader :textobj, :lines

      def self.merge(sparse)
        sparse.group_by(&:textobj).map do |textobj, slines|
          SparseLines.new(textobj, slines.flat_map(&:lines))
        end
      end

      def self.render(sparse)
        merge(sparse).map(&:spifferific).join("\n\n")
      end

      def spifferific
        cooked    = @textobj.spiffier.lines.map(&:chomp)
        base_line = @textobj.lineno
        ranges    = canonicalize_ranges(@lines)
        groups    = ranges.map { |r| cooked[(r.begin - base_line)..(r.end - base_line)] }
        groups    = groups.map! { |g| g.join("\n") }

        loc_width = "#{@textobj.name}:#{ranges.last.begin}: ".length

        groups.zip(ranges).map! do |g, range|
          g.gsub!(/(?<!\A)^/, ' ' * loc_width)
          loc = "#{@textobj.name}:#{range.begin}: "
          "#{Color.bright(loc)}#{g}"
        end.join("\n...\n")
      end

      def canonicalize_ranges(ranges)
        last = nil
        ranges.each_with_object([]) do |range, result|
          if !last || range.begin > last.end + (last.exclude_end? ? 0 : 1)
            result << (last = range)
          else
            range_end = (range.end - (range.exclude_end? ? 1 : 0))
            last_end  = (last.end  - (last.exclude_end?  ? 1 : 0))
            combined = last.begin..(range_end > last_end ? range_end : last_end)
            result[-1] = last = combined
          end
        end
      end
    end
  end
end
