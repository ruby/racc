#
# scanner.rb
#
#     Copyright(c) 1999 Minero Aoki
#     aamine@dp.u-netsurf.ne.jp
#

require 'amstd/bug'
require 'amstd/must'
require 'racc/strscan'



class Scanner

  attr :str

  attr :lineno
  attr :filename, true

  attr :spipe
  attr :vpipe


  EOL   = /\A(\n|\r\n|\r)/o
  SPC   = /\A[ \t]+/o
  LINE  = /\A[^\r\n]*(\n|\r\n|\r|\z)/o
  QPAIR = /\A\\./o
  CHAR  = /\A./o


  def initialize
    @scan = StrScanner.new( '' )
  end


  def reset( str )
    str.must String
    @preserve = str
    @scan.reset( str, false )
    @lineno = 1
    @debug = false
  end

  attr :debug, true


  def scan
  end


  private


  def scan_string( right, preserve = true )
    cont = /\A[^\\#{right}]+/    # don't o
    term = /\A#{right}/          # don't o
    ret = ''

    while true do
      if co = @scan.scan( cont ) then
# puts "cont ---#{co}---"
        ret << co
      end
      if qp = @scan.scan( QPAIR ) then
# puts "bspc ---#{qp}---"
        ret << (preserve ? qp : qp[1, qp.size - 1])
        next
      end
      if ri = @scan.scan( term )
# puts "term ---#{ri}---"
        # ret << ri
        break
      end

      scan_error! 'found unterminated string'
    end

    ret
  end


  def scan_error!( mes )
    raise ScanError, "#{@filename}:#{@lineno}: #{mes}"
  end


  def scan_bug!( mes )
    bug! "#{@filename}:#{@lineno}: #{mes}"
  end


  def debug_report( arr )
    puts "rest=#{@scan.size}"
    sret = arr[0]
    vret = arr[1]
    if Integer === sret then
      puts "sret #{sret.id2name}"
    else
      puts "sret #{sret.inspect}"
    end
    puts "vret #{vret}"
    puts
  end

end
