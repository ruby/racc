#
# $Id$
#
# Copyright (c) 1999-2005 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".
#

require 'racc/exception'

module Racc

  class GrammarFileParser < Parser
    NAMES = %w( header inner footer ) +
            %w( prepare driver )   # obsolete

    def GrammarFileParser.get_usercode(path)
      File.open(path) {|f|
        while line = f.gets
          break if /\A----/ =~ line
        end
        return line ? get_usercode_rec({}, line, f) : {}
      }
    end

    def GrammarFileParser.get_usercode_rec(table, line, f)
      name0, pathes = *line.sub(/\A-+/, '').split('=', 2)
      name = name0.to_s.strip.downcase.slice(/\w+/)
      unless NAMES.include?(name)
        raise CompileError, "unknown type of user code: #{name.inspect}"
      end
      buf = ''
      lineno = f.lineno + 1
      while line = f.gets
        break if /\A----/ =~ line
        buf << line
      end
      table[name] = [buf, lineno, (pathes ? pathes.strip.split(' ') : nil)]
      line ? get_usercode_rec(table, line, f) : table
    end
  end

end
