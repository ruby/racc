#
# scanner.rb
#
#   Copyright (c) 1999,2000 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#
#   This program is free software.
#   You can distribute/modify this program under the terms of
#   the GNU Lesser General Public License version 2 or later.
#

require 'amstd/bug'
require 'strscan'


unless defined? ScanError then
  class ScanError < StandardError; end
end

module Racc

class Scanner

  EOL   = /\A(?:\n|\r\n|\r)/o
  SPACE = /\A[ \t]+/o
  LINE  = /\A[^\r\n]*(?:\n|\r\n|\r|\z)/o
  QPAIR = /\A\\./o
  CHAR  = /\A./o


  def initialize( str, fname = nil )
    @avoid_gc = str   # no need but
    @scan     = StringScanner.new( str, false )
    @filename = fname
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


  def do_scan_string( contexp, termexp, preserve )
    ret = ''
    tmp = nil
    qpair = QPAIR

    while true do
      if tmp = @scan.scan( contexp ) then
        ret << tmp
      end

      if tmp = @scan.scan( qpair ) then
        ret << (preserve ? tmp : tmp[1, tmp.size - 1])

      elsif @scan.skip( termexp )
        break

      else
        scan_error! 'found unterminated string'
      end
    end

    ret
  end

  def scan_string( right, preserve = true )
    do_scan_string( /\A[^\\#{right}]+/, /\A#{right}/, preserve )
  end

  def scan_Q_string( preserve = true )
    do_scan_string( /\A[^\\"]+/, /A"/, preserve )
  end


  def scan_error!( mes )
    raise ScanError, "#{@filename}:#{@lineno}: #{mes}"
  end

  def scan_bug!( mes = 'must not happen' )
    bug! "#{@filename}:#{@lineno}: #{mes}"
  end

  def debug_report( arr )
    s = arr[0]
    printf "%7d %-10s %s\n",
      @scan.restsize,
      s.respond_to?(:id2name) ? s.id2name : s.inspect,
      arr[1].inspect
  end

end

end   # module Racc
