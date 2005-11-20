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

unless File.respond_to?(:read)
  def File.read(filename)
    File.open(filename) {|f| return f.read }
  end
end
