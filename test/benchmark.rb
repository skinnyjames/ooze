# class BenchmarkTest < Oozey::Test
#   LINE = ((("x" * 79) + "\r\n") * 50_000).freeze
#   test "sanity  (full)" do
#     session = parse("", rows: 24, cols: 80)

#     # session.screen.define_singleton_method(:print) { |_| }
#     start = Hokusai.monotonic
#     session.screen.skip_evict = true
#     session.parser.parse(LINE)  
#     stop = Hokusai.monotonic

#     expect(stop - start).to be_less_than(2)
#   end

#   test "sanity (stub screen print proc)" do
#     session = parse("", rows: 24, cols: 80)

#     session.screen.define_singleton_method(:print) { |_| }
#     session.screen.skip_evict = true
#     start = Hokusai.monotonic
#     session.parser.parse(LINE)  
#     stop = Hokusai.monotonic

#     expect(stop - start).to be_less_than(2)
#   end

#     test "sanity  (stub screen print method)" do
#     session = parse("", rows: 24, cols: 80)
#     class << session.screen
#       def print(_); end
#     end
#     start = Hokusai.monotonic
#     session.parser.parse(LINE)  
#     stop = Hokusai.monotonic

#     expect(stop - start).to be_less_than(2)
#   end

#   test "sanity each_codepoint" do
#     start = Hokusai.monotonic
#     LINE.codepoints_each {|f| }
#     stop = Hokusai.monotonic

#     expect(stop - start).to be_less_than(2)
#   end
# end