class InputTest < Oozey::Test
  let(:pty) do
    Struct.new(:rows, :cols).new(50, 50)
  end

  let(:session) do
    Ooze::Terminal::Session.new(pty)
  end
  
  test "basic ansi" do
    expect(session.input.prev_screen.pack("C*")).to eql("\e[5~")
  end
end