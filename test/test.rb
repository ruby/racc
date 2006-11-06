# Racc tester

class TestFailed < StandardError; end

def main
  setup_dirs
  try %w( syntax.y -v               ), [0,0,0,0,0]
  try %w( percent.y                 ), [], true
  try %w( scan.y                    ), [], true
  try %w( newsyn.y                  ), []
  try %w( normal.y                  ), []
  try %w( normal.y -vg              ), []
  try %w( chk.y    -vg              ), [], true
  try %w( chk.y  --line-convert-all ), [], true
  try %w( echk.y   -E               ), [], true
  try %w( err.y                     ), [], true
  try %w( mailp.y                   ), []
  try %w( conf.y   -v               ), [4,1,1,2]
  try %w( rrconf.y                  ), [1,1,0,0]
  try %w( useless.y                 ), [0,0,1,2]
  try %w( opt.y                     ), [], true
  try %w( yyerr.y                   ), [], true
  try %w( recv.y                    ), [5,10,1,4]
  try %w( ichk.y                    ), [], true
  try %w( intp.y                    ), [], true
  try %w( expect.y                  ), [1,0,0,0,1]
  try %w( nullbug1.y                ), [0,0,0,0]
  try %w( nullbug2.y                ), [0,0,0,0]
  try %w( firstline.y               ), []
  try %w( nonass.y                  ), [], true
  try %w( digraph.y                 ), [], true
  try %w( noend.y                   ), []
  assert_fail 'norule.y'
  assert_fail 'unterm.y'
  report
end

def setup_dirs
  clean 'log'
  clean 'tab'
  clean 'out'
  clean 'err'
end

def try(args, ok, exec = false)
  targ = args[0].split('.')[0]
  testing(targ) {
    compile_test args, ok
    if exec
      testing(targ) {
        exec_test targ
      }
    end
  }
end

def compile_test(args, ok)
  fname = args.shift
  n = fname.sub(/\.y\z/, '')
  args.push '-Oout/' + n
  args.push '-otab/' + n
  args.unshift '-Do'
  args.push fname

  racc args.join(' ')
  File.foreach("log/#{fname}") do |line|
    line.strip!
    case line
    when /sr/ then assert_equal "sr#{ok[0]}", line
    when /rr/ then assert_equal "rr#{ok[1]}", line
    when /un/ then assert_equal "un#{ok[2]}", line
    when /ur/ then assert_equal "ur#{ok[3]}", line
    when /ex/ then assert_equal "ex#{ok[4]}", line
    else
      raise TestFailed, 'racc outputs unknown debug report???'
    end
  end
end

def exec_test(file)
  ruby 'tab/' + file
end

@n_test = 0
@n_ok = 0
@errors = []
@target = nil

def testing(name)
  return unless target?(name)
  @target = name
  $stderr.print '.'
  @n_test += 1
  begin
    yield
    @n_ok += 1
  rescue TestFailed
    err = $!
    $stderr.print 'F'
    @errors.push [@target, err.message]
  end
end

def target?(name)
  ARGV.empty? or ARGV.include?(name)
end

def report
  if @n_test == @n_ok
    printf "\nOK %d/%d tests\n", @n_ok, @n_test
  else
    printf "\n%d errors\n", @errors.size
    @errors.each do |targ, msg|
      puts targ + ' fail: ' + msg
    end
  end
end

def assert_equal(expected, real)
  unless real == expected
    raise TestFailed, "expected #{expected.inspect} but was #{real.inspect}"
  end
end

def assert_fail(file)
  testing(file.split(/\./)[0]) {
    begin
      racc file
    rescue TestFailed
    else
      raise TestFailed, 'error not raised'
    end
  }
end

$ruby = ENV['RUBY'] || 'ruby'

def ruby(arg)
  cmd = "#{$ruby} #{arg}"
  str = "#{cmd} 2>> err/#{@target}"
  # $stderr.puts str
  system str or raise TestFailed, "'#{cmd}' failed"
end

$racc = ENV['RACC'] || 'racc'
#$racc += ' --no-extentions' if ENV['NORUBYEXT']

def racc(arg)
  ruby "-S #{$racc} #{arg}"
end

begin
  require 'fileutils'
  include FileUtils
rescue LoadError
  def rm_rf(path)
    system "rm -rf '#{path}'"
  end
end

def clean(dir)
  rm_rf dir
  Dir.mkdir dir
end

main
