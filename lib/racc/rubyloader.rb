#
# rubyloader.rb
#
# Copyright (c) 1999-2003 Minero Aoki <aamine@loveruby.net>
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.
# For details of the GNU LGPL, see the file "COPYING".
#
# $ amstd Id: rubyloader.rb,v 1.5 2003/05/26 14:14:57 aamine Exp $
#

require 'rbconfig'


module RubyLoader

  module_function

  def find_feature( feature )
    with_ext(feature) do |fname|
      $LOAD_PATH.each do |dir|
        path = dir + '/' + fname
        return path if File.file? path
      end
    end

    nil
  end

  def provided?( feature )
    with_ext(feature) do |filename|
      return true if $".index(filename)
    end
    false
  end

  alias required? provided?

  def provide( feature )
    $".push feature
  end

  def with_ext( feature )
    if /\.(?:rb|#{Config::CONFIG['DLEXT']})\z/o === feature
      yield feature
    else
      [ 'rb', Config::CONFIG['DLEXT'] ].each do |ext|
        yield feature + '.' + ext
      end
    end
  end

end
