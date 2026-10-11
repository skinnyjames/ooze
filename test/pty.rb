class PTYTest < Oozey::Test
  def session
    @session 
  end

  def poll(timeout, &block)
    timer = Hokusai::Util::Timer.new

    while !timer.elapsed(timeout)
      break if block.call
    end
  end

  def read_for(session, timeout)
    timer = Hokusai::Util::Timer.new

    while !timer.elapsed(timeout)
      @session.read
    end
  end

  before_each do
    @pty&.close
    @pty = PTY.spawn("bash", 5, 20)
    @session = Ooze::Terminal::Session.new(@pty)
  end

  after_each do
    @pty&.close
    @pty = nil
  end

  test "basic echo" do
    @session.write("echo 'He😆llo'\n")
    read_for(@session, 0.5)

    # Check the rows for the output
    rows = session.screen.lines.map {|line| row(line) }
    expect(rows).to include("He😆*llo")

    puts render(session)
  end

  test "exit from pty" do
    read_for(@session, 0.2)
    @session.write("exit 3\n")
    read_for(@session, 0.3)

    poll(0.5) do
      @session.pty.exited?
    end

    expect(@session.pty.exited?).to eql(3)
  end

  test "exit from ruby" do
    read_for(@session, 0.2)
    @session.pty.close

    poll(0.5) do
      @session.pty.exited?
    end

    expect(@session.pty.exited?).to eql(129)
  end
end