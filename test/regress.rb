#!/usr/bin/env ruby

require 'fileutils'
require 'tempfile'
require 'rainbow'

filename, commit1, commit2 = *ARGV

def croak(message)
  $stderr.puts(message)
  exit 1
end

def trysystem(command)
  croak("Command failed: #{command}") unless system(command)
end

croak("No such file: #{filename}") if !File.exist?(filename)

if commit1.nil? || commit1.empty? || commit2.nil? || commit2.empty?
  croak("Usage: regress.rb <filename> <commit 1> <commit 2>")
end

racc = File.join(File.dirname(__FILE__), '..', 'bin', 'racc')
racc_lib = File.join(File.dirname(__FILE__), '..', 'lib')
temp1 = Tempfile.new('racc-regress')
temp2 = Tempfile.new('racc-regress')

trysystem("git checkout #{commit1}")
trysystem("ruby -I#{racc_lib} #{racc} -o #{temp1.path} #{filename}")

trysystem("git checkout #{commit2}")
trysystem("ruby -I#{racc_lib} #{racc} -o #{temp2.path} #{filename}")

success = system("diff #{temp1.path} #{temp2.path}")

temp1.unlink
temp2.unlink

if success
  puts Rainbow("No change for #{filename}").green
  exit 0
else
  puts Rainbow("Output changed for #{filename}").red
  exit 1
end
