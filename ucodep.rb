#
# ucodep.rb
#
#   Copyright (c) 2000 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#
#   This program is free software.
#   You can distribute/modify this program under the terms of
#   the GNU Lesser General Public License version 2 or later.
#

module Racc

  class RaccParser

    def self.get_ucode( fname )
      ret = {}
      re = /\A----+\s*(header|inner|footer|prepare|driver)\s*(=)?/i
      str = nil
      lineno = 0

      File.foreach( fname ) do |line|
        lineno += 1
        if m = re.match(line) then
          ret[ m[1].downcase ] = [
              (str = ''),
              lineno + 1,
              (m[2] ?  m.post_match.strip.split(/\s+/) : nil)
          ]
        else
          str << line if str
        end
      end

      ret
    end
  
  end

end
