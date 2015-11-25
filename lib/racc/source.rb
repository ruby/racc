# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of LGPL, see the file "COPYING".

module Racc
  module Source
    class Text < Struct.new(:text, :filename, :lineno)
      def to_s
        "#<Source::Text #{location}>"
      end

      def location
        "#{@filename}:#{@lineno}"
      end
    end
  end
end
