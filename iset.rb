#
# iset.rb
#
#   Copyright (c) 1999-2002 Minero Aoki <aamine@loveruby.net>
#
#   This program is free software.
#   You can distribute/modify this program under the terms of
#   the GNU Lesser General Public License version 2 or later.
#


module Racc

  #
  # ISet
  #
  # indexed set.
  # all items respond to :ident
  #

  class ISet

    def initialize( a = [] )
      @set = a
    end

    attr :set

    def add( i )
      @set[ i.ident ] = i
    end

    def []( key )
      @set[ key.ident ]
    end

    def []=( key, val )
      @set[ key.ident ] = val
    end

    alias include? []
    alias key? []

    def update( other )
      s = @set; o = other.set
      i = t = nil
      o.each_index {|i| if t = o[i] then s[i] = t end }
    end

    def update_a( a )
      s = @set
      i = nil
      a.each {|i| s[ i.ident ] = i }
    end

    def delete( key )
      i = @set[ key.ident ]
      @set[ key.ident ] = nil
      i
    end

    def each( &block )
      @set.compact.each( &block )
    end

    def to_a
      @set.compact
    end

    def to_s
      "[#{@set.compact.join(' ')}]"
    end

    alias inspect to_s

    def size
      @set.nitems
    end

    def empty?
      @set.nitems == 0
    end

    def clear
      @set.clear
    end

    def dup
      ISet.new @set.dup
    end
  
  end   # class ISet

end   # module Racc
