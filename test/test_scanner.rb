require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

# The complicated part of the grammar file scanner is dealing with Ruby code
# blocks, so that is what we focus on testing

module Racc
  class TestScanner < TestCase
    Dir[File.join(File.dirname(__FILE__), 'scandata', '*')].each do |testfile|
      define_method("test_scan_#{File.basename(testfile)}".to_sym) do
        original = File.read(testfile)
        # wrap the Ruby source code in an action block
        wrapped  = "class Test\nrule\na : '*' {" + original + "\n}"
        file     = Source::Buffer.new(testfile, wrapped)
        scanner  = Racc::GrammarFileScanner.new(file)

        rebuilt = String.new
        scanner.yylex do |token|
          break if token.nil?
          rebuilt << token[1][0].text if token[0] == :ACTION
        end
        rebuilt.chomp!("\n")

        assert_equal original, rebuilt
      end
    end
  end
end
