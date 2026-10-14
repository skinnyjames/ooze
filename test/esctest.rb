require_relative "./helpers/session_helpers"

class SpecTest
  include Theorem::Hypothesis
  include Matchers
  include SessionHelpers

  test "run esctest.py" do
    dir = ENV["ESCTEST_DIR"] || "../esctest2/esctest"
    log = ENV["ESCTEST_LOG"] || "../../ooze/fail.log"
    session = Ooze::Terminal::Session.spawn(24, 80)
    session.write "cd #{dir} && python3 esctest.py --expected-terminal=xterm --logfile=#{log}; cat #{log}; exit\r"
  
    until session.pty.exited?
      session.read
    end
  end
end

eval ruby_file("ooze/terminal.rb"), binding

results = SpecTest.run!
Theorem::StdoutReporter.report_summary(results)


