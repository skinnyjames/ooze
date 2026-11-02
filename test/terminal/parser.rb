class ParserTest < Oozey::Test
  UNICODE_REPLACE = "\uFFFD"
  let(:pty) do
    Struct.new(:size).new([50, 50])
  end

  let(:session) do
    Ooze::Terminal::Session.new(pty)
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

  test "Ground GL print takes the fast path" do
    printed = []
    session.define_singleton_method(:print) { |cp| printed << cp }
    session.parser.parse("abc".freeze)
    expect(printed).to eql("abc".codepoints)

    tokens = parse("Ooze")
    expect(tokens.size).to be(0)
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
    printed = []
    session.define_singleton_method(:print) { |cp| printed << cp }
    session.parser.parse("中é\u00A0".freeze)
    expect(printed).to eql("中é\u00A0".codepoints)
  end

  test "Terminal modes come froim csi_dispatch actions" do
    parse("\e[2a") do |action, i|
      expect(action.type).to eql(:csi_dispatch)
    end
  end
end