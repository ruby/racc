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

require 'racc/compat'
require 'racc/grammarfileparser'
require 'racc/grammar'
require 'racc/state'
require 'racc/output'

module Racc

  class Compiler

    def initialize
      @filename = nil

      @parser = nil
      @ruletable = nil
      @symboltable = nil
      @statetable = nil
      @formatter = nil

      @debug_parser = false
      @verbose      = false
      @convert_line = true
      @omit_action  = true
      @result_var   = true

      @debug   = false
      @d_parse = false
      @d_rule  = false
      @d_token = false
      @d_state = false
      @d_la    = false
      @d_prec  = false
    end

    attr_reader :filename

    attr_reader :parser
    attr_reader :ruletable
    attr_reader :symboltable
    attr_reader :statetable
    attr_reader :formatter

    attr_accessor :debug_parser
    attr_accessor :verbose
    attr_accessor :convert_line
    attr_accessor :omit_action
    attr_accessor :result_var
    
    attr_accessor :debug
    attr_accessor :d_parse
    attr_accessor :d_rule
    attr_accessor :d_token
    attr_accessor :d_state
    attr_accessor :d_la
    attr_accessor :d_prec

    def parse(str, fname = '-')
      $stderr.puts 'parsing grammar file...' if @verbose

      # must be this order
      @symboltable = SymbolTable.new(self)
      @ruletable   = RuleTable.new(self)
      @parser      = GrammarFileParser.new(self)

      @filename = fname
      @parser.parse(str)
    end

    def compile
      nfa
      dfa
    end

    def nfa
      $stderr.puts 'initializing state machine...' if @verbose
      @statetable = StateTable.new(self)
      @ruletable.init
      @statetable.init
    end

    def dfa
      if @verbose
        $stderr.puts "resolving #{@statetable.size} states..."
        b = Process.times.utime
      end
      @statetable.determine
      if @verbose
        e = Process.times.utime
        $stderr.puts "all resolved in #{e - b} sec"
      end
    end

    def source(f)
      $stderr.puts 'creating table file...' if @verbose
      CodeGenerator.new(self).output f
    end

    def output(f)
      $stderr.puts 'creating .output file...' if @verbose
      VerboseOutputter.new(self).output f
    end

  end

end   # module Racc
