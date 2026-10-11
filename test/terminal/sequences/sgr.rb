class SGRSequenceTest < Oozey::Test
  test "reset" do
    session = parse("CSI 1 m", rows: 5, cols: 10)
    expect(session.screen.current_style.bold).to be(true)
    parse("CSI m", using: session)
    expect(session.screen.current_style.bold).to be(false)
  end

  test "set multiple params" do
    session = parse("CSI 1 ; 4 ; 31 m", rows: 5, cols: 10)
    palette = Ooze::Terminal::Colors.palette
    expect(session.screen.current_style.bold).to be(true)
    expect(session.screen.current_style.underline).to be(true)
    expect(session.screen.current_style.foreground(palette)).to eql(Ooze::Terminal::Colors::RED)

    parse("CSI 22 m", using: session)
    expect(session.screen.current_style.bold).to be(false)
  end

  test "set rgb with rich pallete" do
    session = parse("CSI 38 ; 2 ; 10 ; 20 ; 30 m")
    palette = Ooze::Terminal::Colors.rich_palette
    expect(session.screen.current_style.foreground(palette)).to eql([10, 20, 30])
  end
end