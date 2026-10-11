class ESCSequenceTest < Oozey::Test
  test "changes charset" do
    session = parse("esc ( 0")
    expect(session.charset).to eql(:dec_graphics)
    
    parse("esc ( B", using: session)
    expect(session.charset).to eql(:ascii)
  end

  test "hard reset" do
    session = parse("CSI 4 h CSI 1 m CSI 2 ; 3 r esc ( 0 'hello' CSI 3 ; 3 H", rows: 3, cols: 5)
    expect(render(session).strip).to eql <<~EOF.strip
| 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| ␤ | ␊ | ┌ | ┌ | ⎺ |
| 1 | 1 | 1 | 1 | 1 |
|---|---|---|---|---|
|   |   |   |   |   |
|   |   |   |   |   |
|---|---|---|---|---|
|   |   |   |   |   |
|   |   |   |   |   |
|---|---|---|---|---|
    EOF
    parse("esc c", using: session)
    expect(session.modes[:irm]).to be(false)
    expect(session.screen.cursor.col).to be(0)
    expect(session.screen.cursor.row).to eql(0)
    parse("q", using: session)
  
    expect(render(session).strip).to eql <<~EOF.strip
| 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| q |   |   |   |   |
| 0 |   |   |   |   |
|---|---|---|---|---|
|   |   |   |   |   |
|   |   |   |   |   |
|---|---|---|---|---|
|   |   |   |   |   |
|   |   |   |   |   |
|---|---|---|---|---|
    EOF
  end

  test "index", tags: [:pending] do
  end

  test "reverse_index", tags: [:pending] do
  end

  test "save/restore cursor" do
    session = parse("CSI 3 ; 3 H esc 7 CSI 5 ; 5 H esc 8", rows: 10, cols: 10)
    expect(session.screen.cursor.col).to eql(2)
    expect(session.screen.cursor.row).to eql(2)
  end

  test "deckpam set/reset" do
    session = parse("esc =")
    expect(session.modes[:deckpam]).to be(true)
    parse("esc >", using: session)
    expect(session.modes[:deckpam]).to be(false)
  end
end