# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the same terms of ruby.
# see the file "COPYING".

module Racc
  class CompileError < StandardError; end
  class ScanError    < CompileError;  end
  class ParseError   < CompileError;  end
end
