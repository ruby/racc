require 'mkmf'

have_func('rb_ary_subseq')

create_makefile 'racc/cparse'
