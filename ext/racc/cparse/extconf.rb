# $Id$

require 'rbconfig'

ENV["ARCHFLAGS"] = Config::CONFIG["CFLAGS"].scan(/-arch \S+/).join(" ")

require 'mkmf'

create_makefile 'racc/cparse/cparse'
