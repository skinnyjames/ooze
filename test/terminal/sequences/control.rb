class ControlSequenceTest < Oozey::Test
  test "cr homes cursor col" do
    session = parse("'abcdef' cr", rows: 2, cols: 6)
    expect(session.screen.cursor.col).to eql(0)
  end

  test "bel rings" do
    session = parse("'abc'", rows: 2, cols: 3)
    test = nil
    session.on_bell do
      test = :yeah
    end

    parse("bel", using: session)
    expect(test).to eql(:yeah)
  end

  test "bs moves cursor back 1" do
    session = parse("'abcdef' bs", rows: 2, cols: 6)
    expect(session.screen.cursor.col).to eql(4)
  end

  test "sub prints a ?" do
    session = parse("'ab' sub", rows: 1, cols: 4)
    expect(row(session.screen.current_line)).to eql("ab?")
  end
end