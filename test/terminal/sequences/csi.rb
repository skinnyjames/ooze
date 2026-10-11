class CSISequenceTest < Oozey::Test
  test "set/reset mode works on ansi mode" do
    session = parse("CSI 4 h")
    expect(session.modes[:irm]).to eql(true)
    expect(session.modes[:decsclm]).to eql(false)

    parse("CSI 4 l", using: session)
    expect(session.modes[:irm]).to eql(false)
    expect(session.modes[:decsclm]).to eql(false)
  end

  test "set/reset mode works on dec mode" do
    session = parse("CSI ? 4 h")
    expect(session.modes[:decsclm]).to eql(true)
    expect(session.modes[:irm]).to eql(false)

    parse("CSI ? 4 l", using: session)
    expect(session.modes[:irm]).to eql(false)
    expect(session.modes[:decsclm]).to eql(false)
  end

  test "Cursor movement" do
    {
      "CSI 5 B" => [5, 0],
      "CSI 5 B CSI 1 A" => [4, 0],
      "CSI B" => [1, 0],
      "CSI 0 B" => [1, 0],
      "CSI 5 C" => [0, 5],
      "CSI 5 C CSI 1 D" => [0, 4], 
      "CSI 5 ; 4 H" => [4, 3], # CUP is 1 indexed
      "CSI 1 B CSI 5 G" => [1, 4],
      "CSI 5 ; 4 H CSI 3 d" => [2, 3]
    }.each do |str, check|
      session = parse(str, rows: 10, cols: 10)
      row, col = check

      expect(session.screen.cursor.row).to eql(row)
      expect(session.screen.cursor.col).to eql(col)
    end
  end

  test "scroll down" do
    session = parse("'abcdef'", rows: 2, cols: 6)

    expect(render(session).strip).to eql <<~EOF.strip
| 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| a | b | c | d | e | f |
| 0 | 0 | 0 | 0 | 0 | 0 |
|---|---|---|---|---|---|
|   |   |   |   |   |   |
|   |   |   |   |   |   |
|---|---|---|---|---|---|
    EOF

    # Scroll down
    parse("CSI 1 T", using: session)

    expect(render(session).strip).to eql <<~EOF.strip
| 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
|   |   |   |   |   |   |
|   |   |   |   |   |   |
|---|---|---|---|---|---|
| a | b | c | d | e | f |
| 0 | 0 | 0 | 0 | 0 | 0 |
|---|---|---|---|---|---|
    EOF

    # AGAIN!
    parse("CSI 1 T", using: session)

    # Adios!
    expect(render(session).strip).to eql <<~EOF.strip
| 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
|   |   |   |   |   |   |
|   |   |   |   |   |   |
|---|---|---|---|---|---|
|   |   |   |   |   |   |
|   |   |   |   |   |   |
|---|---|---|---|---|---|
    EOF
  end


  test "scroll up" do
    # move cursor to row 2, type, and scroll up
    session = parse("CSI 1 B 'abcdef' CSI 1 S", rows: 2, cols: 6)

    expect(render(session).strip).to eql <<~EOF.strip
| 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| a | b | c | d | e | f |
| 0 | 0 | 0 | 0 | 0 | 0 |
|---|---|---|---|---|---|
|   |   |   |   |   |   |
|   |   |   |   |   |   |
|---|---|---|---|---|---|
    EOF

    # AGAIN
    parse("CSI 1 S", using: session)

    expect(render(session).strip).to eql <<~EOF.strip
| 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
|   |   |   |   |   |   |
|   |   |   |   |   |   |
|---|---|---|---|---|---|
|   |   |   |   |   |   |
|   |   |   |   |   |   |
|---|---|---|---|---|---|
    EOF

    # our content was evicted to scrollback
    expect(session.screen.scrollback.dig(1, :chars)).to eql("abcdef\n")
  end

  test "set margins" do
    session = parse("'abc' 'def' 'ghi' 'jkl'", rows: 4, cols: 3)
    expect(render(session).strip).to eql <<~EOF.strip
| 0 | 1 | 2 |
|---|---|---|
| a | b | c |
| 0 | 0 | 0 |
|---|---|---|
| d | e | f |
| 0 | 0 | 0 |
|---|---|---|
| g | h | i |
| 0 | 0 | 0 |
|---|---|---|
| j | k | l |
| 0 | 0 | 0 |
|---|---|---|
    EOF

    # set margin on 2-3rd row, goto row 3 and line feed
    parse("CSI 2 ; 3 r CSI 3 ; 1 H lf", using: session)

    expect(render(session).strip).to eql <<~EOF.strip
| 0 | 1 | 2 |
|---|---|---|
| a | b | c |
| 0 | 0 | 0 |
|---|---|---|
| g | h | i |
| 0 | 0 | 0 |
|---|---|---|
|   |   |   |
|   |   |   |
|---|---|---|
| j | k | l |
| 0 | 0 | 0 |
|---|---|---|
    EOF
  end

  test "tabstops" do
    session = parse("CSI 4 G esc H", rows: 1, cols: 10)
    expect(session.screen.tabstops[3]).to eql(true)

    parse("CSI 1 ; 1 H ht", using: session)
    expect(session.screen.cursor.col).to eql(3)

    # clear tabstop under cursor; go bck and tab again
    parse("CSI g CSI 1 ; 1 H ht", using: session)
    expect(session.screen.cursor.col).to eql(8)

    # clear all tabstops
    parse("CSI 3 g CSI 1 ; 1 H ht", using: session)
    expect(session.screen.cursor.col).to eql(9)
  end

  test "insert mode shifts chars to the right" do
    # "abcdef" Ins mode / Set Cursor + Z
    session = parse("'abcdef' CSI 4 h CSI 0 ; 3 H 'Z'", cols: 6)
    expect(row(session.screen.current_line)).to eql("abZcde")
  end

  test "erase_in_line mode 0 erases from cursor to EOL" do
    # print, move cursor back 3 and erase
    session = parse("'abcdef' CSI 2 D CSI 0 K", cols: 6)
    expect(row(session.screen.current_line)).to eql("abc   ")
  end

  test "erase_in_line mode 1 erases from start to cursor" do
    session = parse("'abcdef' CSI 2 D CSI 1 K", cols: 6)
    expect(row(session.screen.current_line)).to eql("    ef")
  end

  test "erase_in_line mode 2 erases whole line" do
    session = parse("'abcdef' CSI 2 D CSI 2 K", cols: 6)
    expect(row(session.screen.current_line)).to eql("      ")
  end
end