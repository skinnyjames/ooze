module Ooze
  module Terminal
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
          decom: false, decawm: true, decarm: false, decpff: false,
          decpex: false, dectcem: true, deckpam: false,
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
  end
end
