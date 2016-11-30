require 'mkmf'
load File.join(File.dirname(__FILE__), '..', '..', 'lib', 'racc', 'info.rb')

have_func('rb_ary_subseq')

$defs.push("-DRACC_VERSION=\"#{Racc::VERSION}\"")

create_makefile 'racc/cparse'
