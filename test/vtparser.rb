class VTParserTest < Ooze::Test
  def parse(str)
    parser = VTParser.new
    tokens = []
    parser.on_parsed do |action|
      tokens << action
    end

    tokens
  end

  # Sanity checks
  test "Parser doesn't hang when input is truncated" do
  end

  test "Parser parses OSC state change" do
  end

  test "Parser parse unicode" do
  end



  # Select Graphic Rendition functions
  test "CSI -> SGR parses basic" do
  end

  test "CSI -> SGR parses style command" do

  end

  test "CSI -> SGR parses style with arguments" do
  end
end