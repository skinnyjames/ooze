class ParserTest < Oozey::Test
  UNICODE_REPLACE = "\uFFFD"
  let(:pty) do
    Struct.new(:rows, :cols).new(50, 50)
  end

  let(:session) do
    Ooze::Terminal::Session.new(pty)
  end

  def dec_code(key)
    0x80 | Ooze::Terminal::DEC_MN_CODE_TABLE[key]
  end

  def code(key)
    Ooze::Terminal::ASCII_CODE_TABLE[key]
  end

  def parse(str)
    tokens = []
    i = 0
    session.parser.on_parse do |action|
      tokens << action
      yield action, i if block_given?
      i += 1
    end

    session.parser.parse(str.freeze)
    tokens
  end

  # Sanity checks
  test "Ground C0 control (bell)" do
    tokens = parse("\x07") do |action, i|
      expect(action.type).to eql(:execute)
    end

    expect(tokens.size).to be(1)
  end

  test "Ground GL print" do
    tokens = parse("Ooze") do |action, i|
      expect(action.type).to eql(:print)
      expected = { 0 => "O", 1 => "o", 2 => "z", 3 => "e" }[i]
      expect(action.content).to eql(expected)
    end

    expect(tokens.size).to be(4)
  end

  # Unicode checks
  test "8-bit C1 won't parse" do
    str = [dec_code(:csi), code("3"), code("1"), code("m")].pack("C*")

    parse(str) do |action, i|
      expected = { 0 => UNICODE_REPLACE, 1 => "3", 2 => "1", 3 => "m" }[i]
      expect(action.type).to eql(:print)
      expect(action.content).to eql(expected)
    end
  end

  test "UTF-8 C1 is ignored" do
    str = [dec_code(:csi), code("3"), code("1"), code("m")].pack("U*")

    parse(str) do |action, i|
      expected = { 0 => "3", 1 => "1", 2 => "m" }[i]
      expect(action.type).to eql(:print)
      expect(action.content).to eql(expected)
    end
  end

  test "8-bit GR won't parse" do
    str = [dec_code("©")].pack("C*")
    parse(str) do |action, i|
      expect(action.type).to eql(:print)
      expect(action.content).to eql(UNICODE_REPLACE)
    end
  end

  # DEC Multinational overlaps with ISO Latin-1
  test "UTF-8 GR (Latin-1)" do
    str = [dec_code("©")].pack("U*")
    parse(str) do |action, i|
      expect(action.type).to eql(:print)
      expect(action.content).to eql("©")
    end
  end

  test "Unicode codepoints at and > GR should print" do
    tokens = parse("中é\u00A0") do |action, i|
      expected = { 0 => "中", 1 => "é", 2 => "\u00A0" }[i]
      expect(action.type).to eql(:print)
      expect(action.content).to eql(expected)
    end
    expect(tokens.size).to eql(3)
  end

  test "Terminal modes come froim csi_dispatch actions" do
    parse("\e[2a") do |action, i|
      expect(action.type).to eql(:csi_dispatch)
    end
  end
end