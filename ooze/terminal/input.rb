module Ooze
  module Terminal
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
      KEYPAD_NUMS[:pf2] = (SS3 + [ASCII_CODE_TABLE['Q']]).freeze
      KEYPAD_NUMS[:pf3] = (SS3 + [ASCII_CODE_TABLE['R']]).freeze
      KEYPAD_NUMS[:pf4] = (SS3 + [ASCII_CODE_TABLE['S']]).freeze
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

      # TODO: Control codes
      # https://www.vt100.net/docs/vt220-rm/chapter3.html#S3.2.5


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
end
