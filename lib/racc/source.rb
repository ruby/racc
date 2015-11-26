# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of LGPL, see the file "COPYING".

module Racc
  module Source
    NL = /\n|\r\n|\r/

    class Buffer < Struct.new(:name, :text)
      def lineno
        1
      end
    end

    class Text < Struct.new(:text, :buffer, :lineno)
      # for source text which didn't come from a file
      def self.from_string(str)
        file = Source::Buffer.new('(string)', str)
        new(str, file, 1)
      end

      def drop_leading_blank_lines
        if blanks = text[/\A(?:[ \t\f\v]*(?:#{NL}))/]
          # $' is post match
          Source::Text.new($', buffer, lineno + blanks.scan(NL).size)
        else
          self
        end
      end

      def name
        buffer.name
      end

      def to_s
        "#<Source::Text #{location}>"
      end

      def location
        "#{name}:#{lineno}"
      end
    end
  end
end
