#
# scanner.rb
#
#   Copyright (c) 1999 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#
#   This program is free software.
#   You can distribute/modify this program under the terms of
#   the GNU Lesser General Public License version 2 or later.
#

require 'amstd/bug'
require 'strscan'


module Racc

class Scanner

  EOL   = /\A(\n|\r\n|\r)/o
  SPC   = /\A[ \t]+/o
  LINE  = /\A[^\r\n]*(\n|\r\n|\r|\z)/o
  QPAIR = /\A\\./o
  CHAR  = /\A./o


  def initialize( str )
    @avoid_gc = str   # no need but
    @scan     = StringScanner.new( str, false )
    @lineno   = 1
    @debug    = false
  end


  attr :lineno
  attr :filename, true

  attr :debug, true

  def scanner
    @scan
  end

  def scan
  end


  private


  def scan_string( right, preserve = true )
    cont = /\A[^\\#{right}]+/    # don't o
    term = /\A#{right}/          # don't o
    ret = ''

    while true do
      if co = @scan.scan( cont ) then
        ret << co
      end
      if qp = @scan.scan( QPAIR ) then
        ret << (preserve ? qp : qp[1, qp.size - 1])
        next
      end
      if ri = @scan.scan( term )
        return ret
      end

      scan_error! 'found unterminated string'
    end
  end


  def scan_error!( mes )
    raise ScanError, "#{@filename}:#{@lineno}: #{mes}"
  end


  def scan_bug!( mes = 'must not happen' )
    bug! "#{@filename}:#{@lineno}: #{mes}"
  end


  def debug_report( arr )
    puts "rest=#{@scan.restsize}"
    s = arr[0]
    puts "token #{Fixnum === s ? s.id2name : s.inspect}"
    puts "value #{arr[1]}"
    puts
  end

end

end   # module Racc
