#
# usercodeparser.rb
#
# Copyright (c) 1999-2004 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".
#

module Racc

  class GrammarFileParser < Parser
    def GrammarFileParser.get_usercode(fname)
      ret = {}
      re = /\A----+\s*(header|inner|footer|prepare|driver)\s*(=)?/i
      str = nil
      lineno = 0

      File.foreach(fname) do |line|
        lineno += 1
        if m = re.match(line)
          ret[m[1].downcase] = [
              str = '',
              lineno + 1,
              (m[2] && !m[2].empty?) ?  m.post_match.strip.split(/\s+/) : nil
          ]
        else
          str << line if str
        end
      end

      ret
    end
  end

end
