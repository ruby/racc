#
# compat.rb
#
# Copyright (c) 1999-2003 Minero Aoki <aamine@loveruby.net>
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.
# For details of the GNU LGPL, see the file "COPYING".
#

unless [].respond_to?(:map!)
  class Array
    if [].respond_to?(:collect!)
      alias map! collect!
    else
      alias map! filter
    end
  end
end

unless [].respond_to?(:map)
  module Enumerable
    alias map collect
  end
end

def bug!( msg )
  raise '[Racc BUG] ' + msg
end
