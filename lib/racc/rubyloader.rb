#
# $amstdId: rubyloader.rb,v 1.6 2004/02/12 14:53:48 aamine Exp $
#
# Copyright (c) 1999-2004 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".
#

require 'rbconfig'

module RubyLoader
  def find_feature(feature)
    candidacy_pathes(feature).find {|path| File.file?(path) }
  end
  module_function :find_feature

  def provided?(feature)
    $".any? {|loaded|
      canonicalize_feature(feature).any? {|feat| feat == loaded }
    }
  end
  module_function :provided?

  alias required? provided?
  module_function :required?

  def provide(feature)
    $".push feature
  end
  module_function :provide

  def candidacy_pathes(feature)
    canonicalize_feature(feature).map {|ent|
      $LOAD_PATH.map {|dir| "#{dir}/#{ent}" }
    }.flatten
  end
  module_function :candidacy_pathes

  def canonicalize_feature(feature)
    if /\.(?:rb|#{Config::CONFIG['DLEXT']})\z/o === feature
      [feature]
    else
      ["#{feature}.rb",
       "#{feature}.#{Config::CONFIG['DLEXT']}"]
    end
  end
  module_function :canonicalize_feature
end
