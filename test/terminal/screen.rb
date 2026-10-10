class TerminalScreenTest < Oozey::Test
  let(:pty) do
    Struct.new(:rows, :cols).new(5, 20)
  end

  def row(line)
    trans = line.codepoints.map do |cp|
      case cp
      when nil
        "_"
      when :continue
        "*"
      else
        cp.chr("UTF-8")
      end
    end

    trans.join("").gsub(/_+$/, "")
  end

  def styles(line)
    line.attrs.reject(&:nil?).join("")
  end

  def insert(line, col, char)
    line.insert(col, char.ord, 0)
    row(line)
  end

  def replace(line, cursor, char)
    line.replace(cursor, char.ord, 0)
    row(line)
  end

  def line(chars, max = 8)
    line = Ooze::Terminal::Line.new(max)
    counter = 0

    chars.split("").each do |char|
      replace(line, counter, char)
      counter += char.width
    end

    line
  end

  def parse(str, rows: 8, cols: 8)
    seq = Ooze::Terminal::SEQ[str].pack("U*").freeze
    pty = Struct.new(:rows, :cols).new(rows, cols)
    session = Ooze::Terminal::Session.new(pty)
    session.parser.parse(seq)
    session
  end

  before_each do
    @session = Ooze::Terminal::Session.new(pty)
    @line = Ooze::Terminal::Line.new(8)
  end

  test "Line#replace at 1" do
    expect(replace(line("abc"), 1, "X")).to eql("aXc")
  end

  test "Line#replace widechar at 1 (start)" do
    expect(replace(line("a中b"), 1, "X")).to eql("aX b")
  end

  test "Line#replace widechar at 2 (continuation)" do
    expect(replace(line("a中b"), 2, "X")).to eql("a Xb")
  end

  test "Line#replace with widechar at 0" do
    expect(replace(line("abc"), 0, "中")).to eql("中*c")
  end

  test "Line#replace 'a文b' with widechar at 0" do
    expect(replace(line("a文b"), 0, "中")).to eql("中* b")
  end

  test "Line#replace at column which makes holes" do
    expect(replace(line(""), 4, "a")).to eql("____a")
  end
  
  test "Line#replace widechars with ascii" do 
    expect(replace(line("中中"), 0, "a")).to eql("a 中*")
  end

  test "Line#insert at a widechar's head shifts it intact" do
    expect(insert(line("a中b", 4), 1, "x")).to eql("ax中*")
  end

  test "Line#insert at a widechar's continuation splits it" do
    expect(insert(line("a中b", 4), 2, "x")).to eql("a x ")
  end

  test "Line#insert keeps a widechar that still fits at the margin" do
    expect(insert(line("a中b", 4), 0, "x")).to eql("xa中*")
  end

  test "Line#insert blanks a widechar cut in half at the margin" do
    expect(insert(line("ab中", 4), 0, "x")).to eql("xab ")
  end

  test "Screen#print style ids are reset for the column work" do
    session = parse("CSI 4 m 'ab' CSI 24 m 'c'", rows: 5, cols: 20)
    expect(styles(session.screen.current_line)).to eql("110")
  end

  test "Screen#print moves cursor" do
    session = parse("'a中b'", rows: 5, cols: 20)
    expect(session.screen.cursor.col).to eql(4)
  end
  
  test "Screen#print doesn't move row at cursor.col == cols (wrap pending)" do
    session = parse("'#{'x' * 20}'", rows: 5, cols: 20)
    expect(session.screen.cursor.row).to eql(0)
    expect(session.screen.cursor.col).to eql(20)
  end

  test "Screen#print moves 1 row down on the next char after row is full" do
    session = parse("'#{'x' * 21}'", rows: 5, cols: 20)
    expect(session.screen.cursor.row).to eql(1)
    expect(session.screen.cursor.col).to eql(1)
  end

  test "Screen#print unicode wraps if width exceeds row" do
    session = parse("'#{'x' * 19}中'", rows: 5, cols: 20)
    expect(session.screen.cursor.row).to eql(1)
    expect(session.screen.cursor.col).to eql(2)
  end

  test "Screen#print autowrap off terminates at margin" do
    session = parse("CSI ? 7 l '#{'x' * 25}'", cols: 20)
    p row(session.screen.current_line)
    expect(session.screen.cursor.row).to eql(0)
    expect(session.screen.cursor.col).to eql(19)
  end

  test "Screen#print CR clears pending wrap and brings cursor to col 0" do
    session = parse("'#{'x' * 20}' cr a", cols: 20)
    expect(session.screen.cursor.row).to eql(0)
    expect(session.screen.cursor.col).to eql(1)
    expect(row(session.screen.current_line)).to eql("a#{'x' * 19}")
  end
  
  test "Screen#print insert mode shifts chars to the right" do
    # "abcdef" Ins mode / Set Cursor + Z
    session = parse("'abcdef' CSI 4 h CSI 0 ; 3 H 'Z'", cols: 6)
    expect(row(session.screen.current_line)).to eql("abZcde")
  end

  test "Cursor movement" do
    {
      "CSI 5 B" => [5, 0],
      "CSI 5 B CSI 1 A" => [4, 0],
      "CSI B" => [1, 0],
      "CSI 0 B" => [1, 0],
      "CSI 5 C" => [0, 5],
      "CSI 5 C CSI 1 D" => [0, 4], 
      "CSI 5 ; 4 H" => [4, 3] # CUP is 1 indexed.. lol
    }.each do |str, check|
      session = parse(str, rows: 10, cols: 10)
      row, col = check

      expect(session.screen.cursor.row).to eql(row)
      expect(session.screen.cursor.col).to eql(col)
    end
  end

  test "Screen#erase_in_line mode 0 erases from cursor to EOL" do
    # print, move cursor back 3 and erase
    session = parse("'abcdef' CSI 2 D CSI 0 K", cols: 6)
    expect(row(session.screen.current_line)).to eql("abc   ")
  end

  test "Screen#erase_in_line mode 1 erases from start to cursor" do
    session = parse("'abcdef' CSI 2 D CSI 1 K", cols: 6)
    expect(row(session.screen.current_line)).to eql("    ef")
  end

  test "Screen#erase_in_line mode 2 erases whole line" do
    session = parse("'abcdef' CSI 2 D CSI 2 K", cols: 6)
    expect(row(session.screen.current_line)).to eql("      ")
  end

  test "Screen evicts chars into scrollback" do
    session = parse("'abcdefghi'", rows: 2, cols: 3)
    expect(session.screen.scrollback.size).to eql(1)
    expect(session.screen.scrollback[0][:chars]).to eql("abc\n")
  end

  test "Screen evicts holes as spaces into scrollback" do
    session = parse("'a' CSI 2 C 'bcdefgh'", rows: 2, cols: 3)
    expect(session.screen.scrollback.size).to eql(1)
    expect(session.screen.scrollback[0][:chars]).to eql("a b\n")
  end

  test "Screen tokenizes scrollback" do
    session = parse("CSI 4 m 'a' CSI 24 m 'bcdefghi'", rows: 2, cols: 3)
    expect(session.screen.scrollback.size).to eql(2)
    expect(session.screen.scrollback[0][:chars]).to eql("a")
    expect(session.screen.scrollback[0][:style].underline).to be(true)
    expect(session.screen.scrollback[1][:chars]).to eql("bc\n")
    expect(session.screen.scrollback[1][:style].underline).to be(false)
  end

  test "SEQ translates DEC special graphics" do
    expect(Ooze::Terminal::SEQ["l q q k", charset: :dec_graphics]).to eql("┌──┐".codepoints)
    expect(Ooze::Terminal::SEQ["esc [ A", charset: :dec_graphics]).to eql(Ooze::Terminal::SEQ["esc [ A"])
  end

  test "Session prints DEC special graphics" do
    session = parse("esc ( 0 l q q k esc ( B q", rows: 2, cols: 8)
    expect(session.screen.lines[0].to_s).to eql("┌──┐q")
  end

  test "SEQ" do
    @session.parser.parse(Ooze::Terminal::SEQ["CSI 4 m 'hell中o' CSI 24 m 'foobarbazwhat okay' CSI 5 m 'hellomynameissean'"].pack("U*").freeze)
    puts render(@session)
  end

  test "Line#col resolves the correct values for a terminal column" do
    @session.parser.parse("\e[1mfoo中\e[4m barb \e[24mhello".freeze)

    {
      2 => { index: 2, char: "o", width: 1, style_id: 1, offset: 0 },
      3 => { index: 3, char: "中", width: 2, style_id: 1, offset: 0 },
      4 => { index: 3, char: "中", width: 2, style_id: 1, offset: 1 },
      5 => { index: 5, char: " ", width: 1, style_id: 2, offset: 0 },
      16 => nil,
    }.each do |col, expected|
      expect(@session.screen.current_line.col(col)).to eql(expected)
    end

    # debug the grid
    # puts render(@session)
  end
end
