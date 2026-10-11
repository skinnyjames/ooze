class OSCSequenceTest < Oozey::Test
  test "window title" do
    session = parse("'abc' ", rows: 2, cols: 2)
    test = nil
    session.on_window_title do |title|
      test = title
    end

    parse("OSC 2 ; 'what is up?' bel", using: session)
    expect(test).to eql("what is up?")

    parse("OSC 0 ; 'hehe' esc \\", using: session)
    expect(test).to eql("hehe")
  end
end