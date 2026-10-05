module Ooze
  module Terminal
    # Based on the VT220 Programmers reference manual
    # https://www.vt100.net/docs/vt220-rm/

    # ASCII Code table (occupies the C0 range starting on the 1st bit to 7th)
    ASCII_CODE_TABLE = {
      nul: 0x00, soh: 0x01, stx: 0x02, etx: 0x03, eot: 0x04, enq: 0x05,
      ack: 0x06, bel: 0x07, bs: 0x08, ht: 0x09, lf: 0x0A, vt: 0x0B, 
      ff: 0x0C, cr: 0x0D, so: 0x0E, si: 0x0F, dle: 0x10, dc1: 0x11,
      dc2: 0x12, dc3: 0x13, dc4: 0x14, nak: 0x15, syn: 0x16, etb: 0x17,
      can: 0x18, em: 0x19, sub: 0x1A, esc: 0x1B, fs: 0x1C, gs: 0x1D,
      rs: 0x1E, us: 0x1F, sp: 0x20, del: 0x7F,
      '!' => 0x21, '"' => 0x22, "#" => 0x23, '$' => 0x24, '%' => 0x25,
      '&' => 0x26, "'" => 0x27, '(' => 0x28, ')' => 0x29, '*' => 0x2A,
      '+' => 0x2B, ',' => 0x2C, '-' => 0x2D, '.' => 0x2E, '/' => 0x2F,
      '0' => 0x30, '1' => 0x31, '2' => 0x32, '3' => 0x33, '4' => 0x34,
      '5' => 0x35, '6' => 0x36, '7' => 0x37, '8' => 0x38, '9' => 0x39,
      ':' => 0x3A, ';' => 0x3B, '<' => 0x3C, '=' => 0x3D, '>' => 0x3E,
      '?' => 0x3F, '@' => 0x40, 'A' => 0x41, 'B' => 0x42, 'C' => 0x43,
      'D' => 0x44, 'E' => 0x45, 'F' => 0x46, 'G' => 0x47, 'H' => 0x48,
      'I' => 0x49, 'J' => 0x4A, 'K' => 0x4B, 'L' => 0x4C, 'M' => 0x4D,
      'N' => 0x4E, 'O' => 0x4F, 'P' => 0x50, 'Q' => 0x51, 'R' => 0x52,
      'S' => 0x53, 'T' => 0x54, 'U' => 0x55, 'V' => 0x56, 'W' => 0x57,
      'X' => 0x58, 'Y' => 0x59, 'Z' => 0x5A, '[' => 0x5B, '\\' => 0x5C,
      ']' => 0x5D, '^' => 0x5E, '_' => 0x5F, '`' => 0x60, 'a' => 0x61, 
      'b' => 0x62, 'c' => 0x63, 'd' => 0x64, 'e' => 0x65, 'f' => 0x66, 
      'g' => 0x67, 'h' => 0x68, 'i' => 0x69, 'j' => 0x6A, 'k' => 0x6B, 
      'l' => 0x6C, 'm' => 0x6D, 'n' => 0x6E, 'o' => 0x6F, 'p' => 0x70, 
      'q' => 0x71, 'r' => 0x72, 's' => 0x73, 't' => 0x74, 'u' => 0x75, 
      'v' => 0x76, 'w' => 0x77, 'x' => 0x78, 'y' => 0x79, 'z' => 0x7A, 
      '{' => 0x7B, '|' => 0x7C, '}' => 0x7D, '~' => 0x7E, 
    }.freeze

    # DEC Multinational charset  (occupies the C1 - GR range offset by the 8th bit)
    # Actual values are (0x80 | value)
    # LEGACY (Pre Unicode - For reference)
    DEC_MN_CODE_TABLE = {
      ind: 0x04, nel: 0x05, ssa: 0x06, esa: 0x07, hts: 0x08, htj: 0x09,
      vts: 0x0A, pld: 0x0B, plu: 0x0C, ri: 0x0D, ss2: 0x0E, ss3: 0x0F,
      dcs: 0x10, pu1: 0x11, pu2: 0x12, sts: 0x13, cch: 0x14,
      mw: 0x15,  spa: 0x16, epa: 0x17, csi: 0x1B, st: 0x1C, osc: 0x1D,
      pm: 0x1E, apc: 0x1F,
      '¡' => 0x21, '¢' => 0x22, '£' => 0x23, '¥' => 0x25, '§' => 0x27,
      '¤' => 0x28, '©' => 0x29, 'ª' => 0x2A, '«' => 0x2B, '°' => 0x30,
      '±' => 0x31, '²' => 0x32, '³' => 0x33, 'µ' => 0x35, '¶' => 0x36, 
      '·' => 0x37, '¹' => 0x39, 'º' => 0x3A, '»' => 0x3B, '¼' => 0x3C,
      '½' => 0x3D, '¿' => 0x3F, 'À' => 0x40, 'Á' => 0x41, 'Â' => 0x42,
      'Ã' => 0x43, 'Ä' => 0x44, 'Å' => 0x45, 'Æ' => 0x46, 'Ç' => 0x47,
      'È' => 0x48, 'É' => 0x49, 'Ê' => 0x4A, 'Ë' => 0x4B, 'Ì' => 0x4C,
      'Í' => 0x4D, 'Î' => 0x4E, 'Ï' => 0x4F, 'Ñ' => 0x51, 'Ò' => 0x52,
      'Ó' => 0x53, 'Ô' => 0x54, 'Õ' => 0x55, 'Ö' => 0x56, 'Œ' => 0x57,
      'Ø' => 0x58, 'Ù' => 0x59, 'Ú' => 0x5A, 'Û' => 0x5B, 'Ü' => 0x5C,
      'Ÿ' => 0x5D, 'ß' => 0x5F, 'à' => 0x60, 'á' => 0x61, 'â' => 0x62, 
      'ã' => 0x63, 'ä' => 0x64, 'å' => 0x65, 'æ' => 0x66, 'ç' => 0x67, 
      'è' => 0x68, 'é' => 0x69, 'ê' => 0x6A, 'ë' => 0x6B, 'ì' => 0x6C, 
      'í' => 0x6D, 'î' => 0x6E, 'ï' => 0x6F, 'ñ' => 0x71, 'ò' => 0x72, 
      'ó' => 0x73, 'ô' => 0x74, 'õ' => 0x75, 'ö' => 0x76, 'œ' => 0x77, 
      'ø' => 0x78, 'ù' => 0x79, 'ú' => 0x7A, 'û' => 0x7B, 'ü' => 0x7C, 
      'ÿ' => 0x7D
    }.freeze

    # Public: Map for sending codes back to the terminal
    #         https://www.vt100.net/docs/vt220-rm/chapter3.html#S3.2.3
    #
    class Input
      attr_reader :session

      def cmodes
        @control_modes ||= {
          ctrl: false, lock: false, shift: false,
          composing: false
        }
      end

      def initialize(session)
        @session = session
      end

      # Control Sequence Introducer
      # https://en.wikipedia.org/wiki/ANSI_escape_code#Control_Sequence_Introducer_commands
      # Using ASCII represenation instead of C1 set.
      CSI = [ASCII_CODE_TABLE[:esc], ASCII_CODE_TABLE['[']].freeze
      
      # Single Shift G3
      # https://www.vt100.net/docs/vt220-rm/chapter4.html#F4-3
      # Moves the next graphic char from G3 (Graphics 3) into GL (ASCII charset) 
      SS3 = [ASCII_CODE_TABLE[:esc], ASCII_CODE_TABLE['O']].freeze
      
      FIND =  (CSI + [ASCII_CODE_TABLE['1'], ASCII_CODE_TABLE['~']]).freeze
      INSERT_HERE = (CSI + [ASCII_CODE_TABLE['2'], ASCII_CODE_TABLE['~']]).freeze
      DELETE = (CSI + [ASCII_CODE_TABLE['3'], ASCII_CODE_TABLE['~']]).freeze

      # Editing
      SELECT = (CSI + [ASCII_CODE_TABLE['4'], ASCII_CODE_TABLE['~']]).freeze
      PREV_SCREEN = (CSI + [ASCII_CODE_TABLE['5'], ASCII_CODE_TABLE['~']]).freeze
      NEXT_SCREEN = (CSI + [ASCII_CODE_TABLE['6'], ASCII_CODE_TABLE['~']]).freeze

      # Cursor (Normal)
      UP = (CSI + [ASCII_CODE_TABLE['A']]).freeze
      DOWN = (CSI + [ASCII_CODE_TABLE['B']]).freeze
      RIGHT = (CSI + [ASCII_CODE_TABLE['C']]).freeze
      LEFT = (CSI + [ASCII_CODE_TABLE['D']]).freeze
    
      # Cursor (Application)
      APP_UP = (SS3 + [ASCII_CODE_TABLE['A']]).freeze
      APP_DOWN = (SS3 + [ASCII_CODE_TABLE['B']]).freeze
      APP_RIGHT = (SS3 + [ASCII_CODE_TABLE['C']]).freeze
      APP_LEFT = (SS3 + [ASCII_CODE_TABLE['D']]).freeze

      # Function keys
      F6 = (CSI + [ASCII_CODE_TABLE['1'], ASCII_CODE_TABLE['7'], ASCII_CODE_TABLE['~']]).freeze
      F7 = (CSI + [ASCII_CODE_TABLE['1'], ASCII_CODE_TABLE['8'], ASCII_CODE_TABLE['~']]).freeze
      F8 = (CSI + [ASCII_CODE_TABLE['1'], ASCII_CODE_TABLE['9'], ASCII_CODE_TABLE['~']]).freeze
      F9 = (CSI + [ASCII_CODE_TABLE['2'], ASCII_CODE_TABLE['0'], ASCII_CODE_TABLE['~']]).freeze
      F10 = (CSI + [ASCII_CODE_TABLE['2'], ASCII_CODE_TABLE['1'], ASCII_CODE_TABLE['~']]).freeze
      F11 = (CSI + [ASCII_CODE_TABLE['2'], ASCII_CODE_TABLE['3'], ASCII_CODE_TABLE['~']]).freeze
      F11_ALT = (CSI + [ASCII_CODE_TABLE['2'], ASCII_CODE_TABLE['3'], ASCII_CODE_TABLE[:esc]]).freeze
      F12 = (CSI + [ASCII_CODE_TABLE['2'], ASCII_CODE_TABLE['4'], ASCII_CODE_TABLE['~']]).freeze
      F12_ALT = (CSI + [ASCII_CODE_TABLE['2'], ASCII_CODE_TABLE['3'], ASCII_CODE_TABLE[:bs]]).freeze
      F13 = (CSI + [ASCII_CODE_TABLE['2'], ASCII_CODE_TABLE['5'], ASCII_CODE_TABLE['~']]).freeze
      F13_ALT = (CSI + [ASCII_CODE_TABLE['2'], ASCII_CODE_TABLE['3'], ASCII_CODE_TABLE[:lf]]).freeze
      F14 = (CSI + [ASCII_CODE_TABLE['2'], ASCII_CODE_TABLE['6'], ASCII_CODE_TABLE['~']]).freeze
      F15 = (CSI + [ASCII_CODE_TABLE['2'], ASCII_CODE_TABLE['8'], ASCII_CODE_TABLE['~']]).freeze
      F16 = (CSI + [ASCII_CODE_TABLE['2'], ASCII_CODE_TABLE['9'], ASCII_CODE_TABLE['~']]).freeze
      F17 = (CSI + [ASCII_CODE_TABLE['3'], ASCII_CODE_TABLE['1'], ASCII_CODE_TABLE['~']]).freeze
      F18 = (CSI + [ASCII_CODE_TABLE['3'], ASCII_CODE_TABLE['2'], ASCII_CODE_TABLE['~']]).freeze
      F19 = (CSI + [ASCII_CODE_TABLE['3'], ASCII_CODE_TABLE['3'], ASCII_CODE_TABLE['~']]).freeze
      F20 = (CSI + [ASCII_CODE_TABLE['3'], ASCII_CODE_TABLE['4'], ASCII_CODE_TABLE['~']]).freeze

      # Aux Keypad (Numeric Mode)
      # https://www.vt100.net/docs/vt220-rm/chapter3.html#S3.2.3
      KEYPAD_NUMS = {}
      (0..9).each do |num|
        KEYPAD_NUMS[num.to_s] = [ASCII_CODE_TABLE[num.to_s]].freeze
      end
      KEYPAD_NUMS['-'] = [ASCII_CODE_TABLE['-']].freeze
      KEYPAD_NUMS[','] = [ASCII_CODE_TABLE[',']].freeze
      KEYPAD_NUMS['.'] = [ASCII_CODE_TABLE['.']].freeze
      KEYPAD_NUMS[:pf1] = (SS3 + [ASCII_CODE_TABLE['P']]).freeze
      KEYPAD_NUMS[:pf2] = (SS3 + ASCII_CODE_TABLE['Q']).freeze
      KEYPAD_NUMS[:pf3] = (SS3 + ASCII_CODE_TABLE['R']).freeze
      KEYPAD_NUMS[:pf4] = (SS3 + ASCII_CODE_TABLE['S']).freeze
      KEYPAD_NUMS[:enter] = nil # Explicity marking that enter depends on the linefeed mode.
      KEYPAD_NUMS.freeze

      # Aux Keypad (Application Mode)
      # https://www.vt100.net/docs/vt220-rm/chapter3.html#S3.2.3
      KEYPAD_APPS = {}
      {
        '0' => 'p', '1' => 'q', '2' => 'r', '3' => 's', '4' => 't',
        '5' => 'u', '6' => 'v', '7' => 'w', '8' => 'x', '9' => 'y',
        '-' => 'm', ',' => 'l', '.' => 'n', :enter => 'M', :pf1 => 'P',
        :pf2 => 'Q', :pf3 => 'R', :pf4 => 'S'
      }.each do |k, v|
        KEYPAD_APPS[k] = (SS3 + [ASCII_CODE_TABLE[v]]).freeze
      end

      SPACE = [ASCII_CODE_TABLE[:sp]].freeze
      BACKSPACE = [ASCII_CODE_TABLE[:del]].freeze
      TAB = [ASCII_CODE_TABLE[:ht]].freeze

      RETURN_LF_ON = [ASCII_CODE_TABLE[:cr], ASCII_CODE_TABLE[:lf]].freeze
      RETURN_LF_OFF = [ASCII_CODE_TABLE[:cr]].freeze

      # Functions
      def csi = CSI
      def find = FIND
      def insert_here = INSERT_HERE
      def delete = DELETE
      def select = SELECT
      
      # xterm modifiers
      def end = SELECT
      def home = FIND

      def prev_screen = PREV_SCREEN
      def next_screen = NEXT_SCREEN
      def up = session.modes[:decckm] ? APP_UP : UP
      def down = session.modes[:decckm] ? APP_DOWN : DOWN
      def right = session.modes[:decckm] ? APP_RIGHT : RIGHT
      def left = session.modes[:decckm] ? APP_LEFT : LEFT
      def space = SPACE
      def backspace = BACKSPACE
      def tab = TAB
      def keypad(key)
        if session.modes[:deckpam]
          KEYPAD_APPS[key]
        elsif key == :enter
          enter
        else
          KEYPAD_NUMS[key]
        end
      end

      def f6 = F6
      def f7 = F7
      def f8 = F8
      def f9 = F9
      def f10 = F10
      def f11 = F11
      def f12 = F12
      def f13 = F13
      def f14 = F14
      def f15 = F15
      def f16 = F16
      def f17 = F17
      def f18 = F18
      def f19 = F19
      def f20 = F20

      def enter = session.modes[:lnm] ? RETURN_LF_ON : RETURN_LF_OFF
    end
  end

  class Session
    attr_reader :parser, :input

    # Possible Keyboard Modes
    # KAM (Keyboarde Action)
    # IRM (Insert Replace)
    # SRM (Send/Recieve)
    # LNM (Linefeed/Newline)
    # DECCKM (Cursor key) (true for Application mode)
    # DECANM (ANSI/VT52)
    # DECCOLM (Column)
    # DECSCLM (Scrolling)
    # DECSCNM (Screen)
    # DECOM (Origin)
    # DECAWM (Autowrap)
    # DECARM (Autorepeat)
    # DECPFF (Print form feed)
    # DECPEX (Print extent)
    # DECTCEM (Text cursor enable)
    # DECKPAM (Keypad Application mode)
    # DECKPNM (Keypad Numeric mode)
    # DECNRCM (Character set)
    def modes
      @modes ||= {
        kam: false, irm: false, srm: false,
        lnm: false, decckm: false, decanm: false,
        deccolm: false, decsclm: false, decscnm: false,
        decom: false, decawm: false, decarm: false, decpff: false,
        decpex: false, dectcem: false, deckpam: false,
        decnrcm: false,
      }
    end

    attr_reader :pty, :parser, :input

    def initialize(pty)
      @pty = pty
      @parser = Parser.new(self)
      @input = Input.new(self)
    end
  end

  class Parser

    # Public: A Parser action
    #         yielded to the callback provided by 
    #         on_parse
    class Action
    end

    PARSER_CONTROLS = {
      
    }

    attr_reader :private_mode_intermediate_char, :intermediate_chars, :params

    def initialize(session)
      @session = session
      @state = :GROUND
      @intermediate_chars = ''
      @private_mode_intermediate_char = ''
      @params = []
      @ignore_flagged = false
      @on_parse = nil
    end

    def on_parse(&block)
      @on_parse = block
    end

    # Public: Turns a command into an ANSI Sequence for
    #         consumption by the pty
    #
    # command - Symbol or VTParser::Command
    #
    # Returns String
    def send_command(command)
      if command == VTParser::Command
        return command.to_s
      end

      COMMANDS[command]
    end

    # Public: Parses a string and invokes the callback for each action
    # 
    # string - the input string
    #
    # Returns nothing
    def parse(str)
    end
  end
end