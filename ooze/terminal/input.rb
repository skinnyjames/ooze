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
      
      FIND =            SEQ["CSI 1 ~"].freeze
      INSERT_HERE =     SEQ["CSI 2 ~"].freeze
      DELETE =          SEQ["CSI 3 ~"].freeze

      # Editing
      SELECT =          SEQ["CSI 4 ~"].freeze
      PREV_SCREEN =     SEQ["CSI 5 ~"].freeze
      NEXT_SCREEN =     SEQ["CSI 6 ~"].freeze

      # Cursor (Normal)
      UP =              SEQ["CSI A"].freeze
      DOWN =            SEQ["CSI B"].freeze
      RIGHT =           SEQ["CSI C"].freeze
      LEFT =            SEQ["CSI D"].freeze

      # Cursor (Application)
      APP_UP =          SEQ["SS3 A"].freeze
      APP_DOWN =        SEQ["SS3 B"].freeze
      APP_RIGHT =       SEQ["SS3 C"].freeze
      APP_LEFT =        SEQ["SS3 D"].freeze

      # Function keys
      F6 =              SEQ["CSI 1 7 ~"].freeze
      F7 =              SEQ["CSI 1 8 ~"].freeze
      F8 =              SEQ["CSI 1 9 ~"].freeze
      F9 =              SEQ["CSI 2 0 ~"].freeze
      F10 =             SEQ["CSI 2 1 ~"].freeze
      F11 =             SEQ["CSI 2 3 ~"].freeze
      F12 =             SEQ["CSI 2 4 ~"].freeze
      F13 =             SEQ["CSI 2 5 ~"].freeze

      F14 =             SEQ["CSI 2 6 ~"].freeze
      F15 =             SEQ["CSI 2 8 ~"].freeze
      F16 =             SEQ["CSI 2 9 ~"].freeze
      F17 =             SEQ["CSI 3 1 ~"].freeze
      F18 =             SEQ["CSI 3 2 ~"].freeze
      F19 =             SEQ["CSI 3 3 ~"].freeze
      F20 =             SEQ["CSI 3 4 ~"].freeze

      # F11_ALT = (CSI + [ASCII_CODE_TABLE['2'], ASCII_CODE_TABLE['3'], ASCII_CODE_TABLE[:esc]]).freeze
      # F12_ALT = (CSI + [ASCII_CODE_TABLE['2'], ASCII_CODE_TABLE['3'], ASCII_CODE_TABLE[:bs]]).freeze
      # F13_ALT = (CSI + [ASCII_CODE_TABLE['2'], ASCII_CODE_TABLE['3'], ASCII_CODE_TABLE[:lf]]).freeze

      # Aux Keypad (Numeric Mode)
      # https://www.vt100.net/docs/vt220-rm/chapter3.html#S3.2.3
      KEYPAD_NUMS = {}
      (0..9).each do |num|
        KEYPAD_NUMS[num.to_s] = SEQ[num.to_s].freeze
      end
      KEYPAD_NUMS['-'] =  SEQ["-"].freeze
      KEYPAD_NUMS[','] =  SEQ[","].freeze
      KEYPAD_NUMS['.'] =  SEQ["."].freeze
      KEYPAD_NUMS[:pf1] = SEQ["SS3 P"].freeze
      KEYPAD_NUMS[:pf2] = SEQ["SS3 Q"].freeze
      KEYPAD_NUMS[:pf3] = SEQ["SS3 R"].freeze
      KEYPAD_NUMS[:pf4] = SEQ["SS3 S"].freeze
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
        KEYPAD_APPS[k] = SEQ["SS3 #{v}"].freeze
      end

      SPACE =         SEQ["sp"].freeze
      BACKSPACE =     SEQ["del"].freeze
      TAB =           SEQ["ht"].freeze

      RETURN_LF_ON =  SEQ["cr lf"].freeze
      RETURN_LF_OFF = SEQ["cr"].freeze

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
