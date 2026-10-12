module Ooze
  module Terminal
    # Handles all input to the PTY
    #
    # Started VT200 compat, but it's outdated for a lot of use cases.
    # xterm may not be fully implemented.
    class Input
      attr_reader :session
      # https://invisible-island.net/xterm/ctlseqs/ctlseqs.html#h3-PC-Style-Function-Keys
      # https://en.wikipedia.org/wiki/ANSI_escape_code#Terminal_input_sequences
      PC_FUNCTION_KEYS = {
        up:         SEQP["?? ?? A"], 
        down:       SEQP["?? ?? B"], 
        right:      SEQP["?? ?? C"], 
        left:       SEQP["?? ?? D"],
        home:       SEQP["?? ?? H"], 
        end:        SEQP["?? ?? F"], 
        insert:     SEQP["CSI 2 ?? ~"], 
        delete:     SEQP["CSI 3 ?? ~"],
        page_up:    SEQP["CSI 5 ?? ~"], 
        page_down:  SEQP["CSI 6 ?? ~"], 
        f1:         SEQP["?? ?? P"], 
        f2:         SEQP["?? ?? Q"], 
        f3:         SEQP["?? ?? R"], 
        f4:         SEQP["?? ?? S"], 
        f5:         SEQP["CSI 1 5 ?? ~"], 
        f6:         SEQP["CSI 1 7 ?? ~"], 
        f7:         SEQP["CSI 1 8 ?? ~"], 
        f8:         SEQP["CSI 1 9 ?? ~"], 
        f9:         SEQP["CSI 2 0 ?? ~"], 
        f10:        SEQP["CSI 2 1 ?? ~"], 
        f11:        SEQP["CSI 2 3 ?? ~"], 
        f12:        SEQP["CSI 2 4 ?? ~"],
        # back to vt220 keys (For reference)
        # https://www.vt100.net/docs/vt220-rm/chapter3.html
        # We will never get these keys.
        f13:        SEQ["CSI 2 5 ~"],
        f14:        SEQ["CSI 2 6 ~"],
        f15:        SEQ["CSI 2 8 ~"],
        f16:        SEQ["CSI 2 9 ~"],
        f17:        SEQ["CSI 3 1 ~"],
        f18:        SEQ["CSI 3 2 ~"],
        f19:        SEQ["CSI 3 3 ~"],
        f20:        SEQ["CSI 3 4 ~"],
      }

      # 3.2.5 Control Codes
      # https://www.vt100.net/docs/vt220-rm/chapter3.html#S3.2.5
      CTRL_CODES = {
        " " => "nul", "2" => "nul", "a" => "soh", "b" => "stx",
        "c" => "etx", "d" => "eot", "e" => "enq", "f" => "ack",
        "g" => "bel", "h" => "bs", "i" => "ht", "j" => "lf",
        "k" => "vt", "l" => "ff", "m" => "cr", "n" => "so", "o" => "si",
        "p" => "dle", "q" => "dc1", "r" => "dc2", "s" => "dc3", "t" => "dc4",
        "u" => "nak", "v" => "syn", "w" => "etb", "x" => "can", "y" => "em",
        "z" => "sub", "3" => "esc", "[" => "esc", "4" => "fs", "/" => "fs",
        "5" => "gs", "]" => "gs", "6" => "rs", "~" => "rs", "7" => "us", "?" => "us",
        "8" => "del" 
      }

      # Cascade terminal modes
      KEYBOARD = {
        space: "sp", backspace: "del", tab: "ht", escape: "esc",
        enter: "cr"
      }

      KEYBOARD_LNM = {
        enter: "cr lf"
      }

      # Aux Keypad (Numeric Mode)
      # https://www.vt100.net/docs/vt220-rm/chapter3.html#S3.2.3
      # 
      # This is a reference implementation, after all.
      # Let. me. cook.
      KEYPAD_NUMS = {
        kp0: "0", kp1: "1", kp2: "2", kp3: "3", kp4: "4",
        kp5: "5", kp6: "6", kp7: "7", kp8: "8", kp9: "9",
        kpminus: "-", kpcomma: ",", kpperiod: ".", kpenter: "cr"
        # No pf1..etc, raylib doesn't support it and most keyboards don't.
      }

      KEYPAD_NUMS_LNM = {
        kpenter: "cr lf",
      }

      # Aux Keypad (Application Mode)
      # https://www.vt100.net/docs/vt220-rm/chapter3.html#S3.2.3
      KEYPAD_APPS = {
        kp0: 'SS3 p', kp1: 'SS3 q', kp2: 'SS3 r', kp3: 'SS3 s', kp4: 'SS3 t',
        kp5: 'SS3 u', kp6: 'SS3 v', kp7: 'SS3 w', kp8: 'SS3 x', kp9: 'SS3 y',
        kpminus: 'SS3 m', kpcomma: 'SS3 l', kpperiod: 'SS3 n', kpenter: 'SS3 M'
      }

      [CTRL_CODES, KEYBOARD, KEYBOARD_LNM, KEYPAD_NUMS, KEYPAD_NUMS_LNM, KEYPAD_APPS].each do |const|
        const.transform_values! do |value|
          SEQ[value].freeze
        end

        const.freeze
      end
      
      def initialize(session)
        @session = session
      end

      def write(seq)
        session.write seq.pack("U*")
      end

      def keypress(key, modifiers)
        param = modifiers_to_param(modifiers)

        # Function key handling
        if seqp = PC_FUNCTION_KEYS[key]
          case seqp.count
          when 1
            param = param == 1 ? "" : "; #{param}"
            write seqp.complete(["#{param}"])
          when 2
            # Okay, so SS3 can't take parameters
            # so if there are <any> modifiers; switch to CSI.
            # But.
            # If there are no params, we want to use CSI unless cursor key application mode is on
            # Unless. it's F1..F4, then we don't care - SS3.
            param = param == 1 ? "" : "1 ; #{param}"
            prefix = session.modes[:decckm] ? "SS3" : "CSI"

            prefix = "SS3" if [:f1, :f2, :f3, :f4].include?(key) 
            prefix = "CSI" if !param.empty?

            write seqp.complete([prefix, param])
          end
        else
          # Keyboard / Keypad
          if KEYPAD_APPS[key] && session.modes[:deckpam]
            seq = KEYPAD_APPS[key]
          elsif KEYPAD_NUMS[key] && session.modes[:lnm]
            seq = KEYPAD_NUMS_LNM[key] || KEYPAD_NUMS[key]
          elsif KEYPAD_NUMS[key]
            seq = KEYPAD_NUMS[key]
          elsif  KEYBOARD[key] && session.modes[:lnm]
            seq = KEYBOARD_LNM[key] || KEYBOARD[key]
          elsif KEYBOARD[key]
            seq = KEYBOARD[key]
          end

          return unless seq
          seq = SEQ["CSI Z"] if key == :tab && modifiers[:shift]
          seq = SEQ["esc"] + seq if modifiers[:alt]
          write seq
        end
      end

      def print(char, modifiers)
        if modifiers[:control] && (seq = CTRL_CODES[char.downcase])
          seq = SEQ["esc"] + seq if modifiers[:alt]
          write seq
        else
          seq = char.codepoints
          seq = SEQ["esc"] + seq if modifiers[:alt]
          write seq
        end
      end

      def paste(text)
        seq = text.codepoints.reject { |cp| cp == ASCII_CODE_TABLE[:esc] }

        if session.modes[:bracketpaste]
          seq = SEQ["CSI 2 0 0 ~"] + seq + SEQ["CSI 2 0 1 ~"]
        end
        write seq
      end

      def focused(value = true)
        return unless session.modes[:focusevents]

        write SEQ[value ? "CSI I" : "CSI O"]
      end

      # In order to support F1-F5, we also need to support PC style function keys.
      # which means also considering modifiers.
      #
      # In normal mode, i.e., a Sun/PC keyboard when the sunKeyboard resource is
      # false (and none of the other keyboard resources such as oldXtermFKeys
      # resource is set), xterm encodes function key modifiers as parameters
      # appended before the final character of the control sequence.  As a
      # special case, the SS3  sent before F1 through F4 is altered to CSI  when
      # sending a function key modifier as a parameter.
      # Code     Modifiers
      # 2     | Shift
      # 3     | Alt
      # 4     | Shift + Alt
      # 5     | Control
      # 6     | Shift + Control
      # 7     | Alt + Control
      # 8     | Shift + Alt + Control
      # 9     | Meta
      # 10    | Meta + Shift
      # 11    | Meta + Alt
      # 12    | Meta + Alt + Shift
      # 13    | Meta + Ctrl
      # 14    | Meta + Ctrl + Shift
      # 15    | Meta + Ctrl + Alt
      # 16    | Meta + Ctrl + Alt + Shift
      # 
      # Public: Computes the derived CSI params
      #         from a hash of modifiers.
      #         If result is 1, no modifier is present.
      def modifiers_to_param(modifiers)
        flags = 0
        flags |= 1 if modifiers[:shift]
        flags |= 2 if modifiers[:alt]
        flags |= 4 if modifiers[:control]
        flags |= 8 if modifiers[:meta]
        
        flags + 1
      end
    end
  end
end