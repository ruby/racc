class MyParser
rule
stmt: ('a')
end
---- header
require 'strscan'
---- inner
def parse(str)
  @ss = StringScanner.new(str)
  do_parse
end
def next_token
  @ss.skip(/\\s+/)
  token = @ss.scan(/\\S+/) and [token, token]
end
