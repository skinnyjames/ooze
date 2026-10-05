class UTF8Test < Ooze::Test
  test "Integer#charwidth return valid charwidth" do
    expect("a".ord.charwidth).to eql(1)
  end

  test "Integer#charwidth raises on invalid unicode" do
    expect(->() { -1.charwidth }).to(raise_error do |ex|
      expect(ex.class).to eql(RangeError)
    end)

    expect(->() { 1_114_112.charwidth }).to(raise_error do |ex|
      expect(ex.class).to eql(RangeError)
    end)
  end

  {
    "中文" => 4,
    "👨‍👩‍👧" => 6,
    "a\0b" => 2, # Null byte
    "a\xFFb" => 3, # bad byte
  }.each do |str, count|
    test "String#width #{str}.width returns #{count}" do
      expect(str.width).to eql(count)
    end
  end 

  test "String#width Ambigious width" do
    expect("±".width).to eql(2)
    expect("±".width(1)).to eql(1)
  end
end
