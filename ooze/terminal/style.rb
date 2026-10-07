module Ooze
  module Terminal
    # Public: Represents the possible color spaces for a given session
    # https://linuxvox.com/blog/what-is-the-difference-between-xterm-color-xterm-256color/#xterm-color-the-legacy-16-color-standard
    class Colors
      BLACK = [0, 0, 0].freeze
      RED = [226, 81, 144].freeze
      GREEN = [102,206,99].freeze
      YELLOW = [206, 202, 99].freeze
      BLUE = [131, 207, 234].freeze
      MAGENTA = [198, 93, 191].freeze
      CYAN = [133,220,252].freeze
      WHITE = [233, 233, 233].freeze
      BLACK_BRIGHT = [102, 102, 102].freeze
      RED_BRIGHT = [235, 133, 177].freeze
      GREEN_BRIGHT = [148, 221, 146].freeze
      YELLOW_BRIGHT = [221, 218, 146].freeze
      BLUE_BRIGHT = [168, 221, 240].freeze
      MAGENTA_BRIGHT = [215, 142, 210].freeze
      CYAN_BRIGHT = [170, 231, 253].freeze
      WHITE_BRIGHT = [255, 255, 255].freeze

      # Public: An overideable 256 color palette
      #         0..15 are the default 16 colors (4-bit)
      #         16..231 are RGB values
      #         232..255 are Grayscale values
      #
      def self.rich_palette(overrides = {}, &block)
        palette = palette(overrides, &block)

        # Set 256 RGB Space (16..231)
        (0..5).each do |red|
          (0..5).each do |green|
            (0..5).each do |blue|
              c = 16 + (red * 36) + (green * 6) + blue
              r = red > 0 ? red * 40 + 55 : 0
              g = green > 0 ? green * 40 + 55 : 0
              b = blue > 0 ? blue * 40 + 55 : 0

              if block_given?
                palette[c] = yield [r,g,b]
              else
               palette[c] = [r, g, b]
              end
            end
          end
        end

        # Set Grayscale (232..255)
        (0..23).each do |i|
          v = 8 + i * 10
          if block_given?
            palette[232 + i] = yield [v, v, v]
          else
            palette[232 + i] = [v, v, v]
          end
        end

        palette
      end

      # Public: An overideable 16 color palette.
      def self.palette(overrides = {})
        palette = {}

        { 
          black: Colors::BLACK,
          red: Colors::RED,
          green: Colors::GREEN,
          yellow: Colors::YELLOW,
          blue: Colors::BLUE,
          magenta: Colors::MAGENTA,
          cyan: Colors::CYAN,
          white: Colors::WHITE,
          black_bright: Colors::BLACK_BRIGHT,
          red_bright: Colors::RED_BRIGHT,
          green_bright: Colors::GREEN_BRIGHT,
          yellow_bright: Colors::YELLOW_BRIGHT,
          blue_bright: Colors::BLUE_BRIGHT,
          magenta_bright: Colors::MAGENTA_BRIGHT,
          cyan_bright: Colors::CYAN_BRIGHT,
          white_bright: Colors::WHITE_BRIGHT,
        }.each_with_index do |(key, color), idx|
          if block_given?
            palette[idx] = yield overrides[key] || color
          else
            palette[idx] = overrides[key] || color
          end
        end
        
        palette
      end
    end

    # XTermColor (1990s)
    # 4 bit escape codes / color depth
    # 16 colors - 8 base / 8 bright
    # Unsupported colors here will be nil, fallback to UI defaults.
    XTermColors = Colors.palette.freeze

    XTerm256Colors = Colors.rich_palette.freeze

    # Public: Represents an SGR style state
    #         can be applied to a range of chars independently
    #         VT100: https://vt100.net/docs/vt510-rm/SGR.html
    #         Further reading: https://deepwiki.com/iliazeus/vscode-ansi/5.3-sgr-code-reference
    class Style
      PS_MAP = {
        0 => :reset,
        1 => :bold!,
        2 => :faint!,
        3 => :italic!,
        4 => :underline!,
        5 => :blink!,
        7 => :invert!,
        8 => :hide!,
        9 => :strikethrough!,
        # Apparently some terminals read this as bold off
        # But we'll stay true to ANSI
        21 => :double_underline!,
        22 => :normal!,
        23 => :un_italic!,
        24 => :un_underline!,
        25 => :un_blink!,
        27 => :un_invert!,
        28 => :un_hide!,
        29 => :un_strikethrough!,
        30 => :foreground_black,
        31 => :foreground_red,
        32 => :foreground_green,
        33 => :foreground_yellow,
        34 => :foreground_blue,
        35 => :foreground_magenta,
        36 => :foreground_cyan,
        37 => :foreground_white,
        39 => :foreground_default,
        40 => :background_black,
        41 => :background_red,
        42 => :background_green,
        43 => :background_yellow,
        44 => :background_blue,
        45 => :background_magenta,
        46 => :background_cyan,
        47 => :background_white,
        49 => :background_default,
        # Bright colors
        90 => :foreground_bright_black,
        91 => :foreground_bright_red,
        92 => :foreground_bright_green,
        93 => :foreground_bright_yellow,
        94 => :foreground_bright_blue,
        95 => :foreground_bright_magenta,
        96 => :foreground_bright_cyan,
        97 => :foreground_bright_white,
        100 => :background_bright_black,
        101 => :background_bright_red,
        102 => :background_bright_green,
        103 => :background_bright_yellow,
        104 => :background_bright_blue,
        105 => :background_bright_magenta,
        106 => :background_bright_cyan,
        107 => :background_bright_white,
        # special effects
        26 => :proportional!,
        50 => :un_proportional!,
        51 => :framed!,
        52 => :circled!,
        54 => :un_frame!,
        53 => :overline!,
        55 => :un_overline!,
        73 => :superscript!,
        74 => :subscript!,
      }.freeze

      attr_accessor :bold, :italic, :underline, :overline,
                    :blink, :hide, :invert, :double_underline,
                    :strikethrough, :proportional, :framed, :circled, 
                    :superscript, :subscript, :faint, 
                    :font_index

      def initialize
        reset
      end

      def reset
        @foreground = nil
        @background = nil
        @bold = false
        @faint = false
        @italic = false
        @underline = false
        @double_underline = false
        @overline = false
        @strikethrough = false
        @proportional = false
        @framed = false
        @circled = false
        @superscript = false
        @subscript = false
        @blink = false
        @hide = false
        @invert = false
        @font_index = 0
      end

      def foreground(palette)
        case @foreground
        when Integer then palette[@foreground]
        when Array
          if block_given?
            yield @foreground
          else
            @foreground
          end
        end
      end

      def background(palette)
        case @background
        when Integer then palette[@background]
        when Array
          if block_given?
            yield @background
          else
            @background
          end
        end
      end

      def snapshot
        clone
      end

      [:black, :red, :green, :yellow, :blue, :magenta, :cyan, :white].each_with_index do |color, idx|
        define_method("foreground_#{color}") do
          @foreground = idx
        end

        define_method("background_#{color}") do
          @background = idx
        end

        define_method("foreground_bright_#{color}") do
          @foreground = idx + 8
        end

        define_method("background_bright_#{color}") do
          @background = idx + 8
        end
      end

      def foreground_default
        @foreground = nil
      end

      def background_default
        @background = nil
      end

      def bold!
        @faint = false
        @bold = true
      end

      def faint!
        @bold = false
        @faint = true
      end

      def italic!
        @italic = true
      end

      # Public: Removes bold and faint
      #         Note: VT100 refers to this as unbold, because "faint"
      #         did not exist then.
      def normal!
        @bold = false
        @faint = false
      end

      def underline!
        @double_underline = false
        @underline = true
      end

      def double_underline!
        @underline = false
        @double_underline = true
      end

      def blink!
        @blink = true
      end

      def strikethrough!
        @strikethrough = true
      end

      def un_strikethrough!
        @strikethrough = false
      end

      # Swaps foreground and background colors
      def invert!
        @invert = true
      end

      def hide!
        @hide = true
      end

      def un_bold!
        @bold = false
      end

      def un_italic!
        @italic = false
      end

      def un_underline!
        @underline = false
        @double_underline = false
      end

      def un_blink!
        @blink = false
      end

      def un_invert!
        @invert = false
      end

      def un_hide!
        @hide = false
      end

      def proportional!
        @proportional = true
      end

      def un_proportional!
        @proportional = false
      end

      def framed!
        @circled = false
        @framed = true
      end

      def circled!
        @framed = false
        @circled = true
      end

      def un_frame!
        @framed = false
        @circled = false
      end

      def overline!
        @overline = true
      end

      def un_overline!
        @overline = false
      end

      def superscript!
        @subscript = false
        @superscript = true
      end

      def subscript!
        @superscript = false
        @subscript = true
      end

      # Handles Select Graphic Rendition (SGR) codes
      def sgr(params, ps: params.dup)
        if ps.empty?
          reset

          return
        end

        while attr = ps.shift
          case attr
          when 10..19
            @font_index = attr - 10
          when 38
            case ps.shift
            when 5 # foreground color 8-bit
              @foreground = ps.shift
            when 2 # foreground color rgb
              @foreground = [ps.shift || 0, ps.shift || 0, ps.shift || 0]
            end
          when 48
            case ps.shift
            when 5 # background color 8-bit
              @background = ps.shift
            when 2 # background color rgb
              @background = [ps.shift || 0, ps.shift || 0, ps.shift || 0]
            end
          else
            if method = PS_MAP[attr.to_i]
              self.send(method)
            end
            # ignore
            # raise "SGR #{attr} not supported!"
          end
        end
      end

      # Public: key used for hashing the style
      def key
        [
          @foreground, @background, @bold, @faint, @italic, 
          @underline, @double_underline, @overline, @strikethrough,
          @proportional, @framed, @circled, @superscript, @subscript, 
          @blink, @hide, @invert, @font_index
        ]
      end

      def hash
        key.hash
      end

      def eql?(other)
        other.is_a?(Ooze::Terminal::Style) && other.key == key
      end

      alias_method :==, :eql?
    end
  end
end
