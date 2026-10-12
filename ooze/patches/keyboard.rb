module Hokusai
  class Keyboard
    def printable?(type = :pressed)
      [
        :space, :apostrophe, :comma, :minus, :period,
        :slash, :right_bracket, :left_bracket, :grave, :equal,
        :zero, :one, :two, :three, :four, :five, :six, 
        :seven, :eight, :nine, :semicolon, :backslash,
        :a, :b, :c, :d, :e, :f, :g, :h,
        :i, :j, :k, :l, :m, :n, :o, :p, :q, :r, 
        :s, :t, :u, :v, :w, :x, :y, :z,
      ].include?(symbol(type))
    end
  end
end
