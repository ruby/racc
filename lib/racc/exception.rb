# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".

module Racc
  class CompileError < StandardError; end
  class ScanError    < CompileError;  end
  class ParseError   < CompileError;  end
end
