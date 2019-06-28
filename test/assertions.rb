require_relative 'envutil'

module Racc
  class TestCase < Test::Unit::TestCase
    FailDesc = proc do |status, message = "", out = ""|
      pid = status.pid
      now = Time.now
      faildesc = proc do
        if signo = status.termsig
            signame = Signal.signame(signo)
            sigdesc = "signal #{signo}"
        end
        log = EnvUtil.diagnostic_reports(signame, pid, now)
        if signame
            sigdesc = "SIG#{signame} (#{sigdesc})"
        end
        if status.coredump?
            sigdesc = "#{sigdesc} (core dumped)"
        end
        full_message = ''.dup
        message = message.call if Proc === message
        if message and !message.empty?
            full_message << message << "\n"
        end
        full_message << "pid #{pid}"
        full_message << " exit #{status.exitstatus}" if status.exited?
        full_message << " killed by #{sigdesc}" if sigdesc
        if out and !out.empty?
            full_message << "\n" << out.b.gsub(/^/, '| ')
            full_message.sub!(/(?<!\n)\z/, "\n")
        end
        if log
            full_message << "Diagnostic reports:\n" << log.b.gsub(/^/, '| ')
        end
        full_message
      end
      faildesc
    end

    def assert_ruby_status(args, test_stdin="", message=nil, **opt)
      out, _, status = EnvUtil.invoke_ruby(args, test_stdin, true, :merge_to_stdout, **opt)
      desc = FailDesc[status, message, out]
      assert(!status.signaled?, desc)
      message ||= "ruby exit status is not success:"
      assert(status.success?, desc)
    end
  end

  module MiniTest
    Assertion = Test::Unit::AssertionFailedError
  end
end
