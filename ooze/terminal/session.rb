module Ooze
  module Terminal
    class Session
      # Possible Terminal Modes
      # KAM (Keyboard Action)
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
      # DECKPAM (Keypad Application mode) / DECKPNM (Keypad Numeric mode)
      # DECNRCM (Character set)
      def modes
        @modes ||= modes_initial
      end

      def modes_initial
        {
          kam: false, irm: false, srm: false,
          lnm: false, decckm: false, decanm: true,
          deccolm: false, decsclm: false, decscnm: false,
          decom: false, decawm: true, decarm: true, decpff: false,
          decpex: false, dectcem: true, deckpam: false,
          decnrcm: false, altscreen: false, bracketpaste: false,
          focusevents: false,
        }
      end

      def ansi_modemap
        @ansi_modemap ||= { 2 => :kam, 4 => :irm, 12 => :srm, 20 => :lnm, }
      end

      def mode_hooks
        @mode_hooks ||= {
          1047 => { before_enter: :clear_alt_screen },
          1049 => { before_enter: :prepare_alt_screen }
        }
      end

      def dec_modemap
        @dec_modemap ||= {               
          1 => :decckm, 3 => :deccolm, 4 => :decsclm,
          5 => :decscnm, 6 => :decom, 7 => :decawm, 
          8 => :decarm, 18 => :decpff, 19 => :decpex, 
          25 => :dectcem, 42 => :decnrcm, 1049 => :altscreen,
          47 => :altscreen, 1047 => :altscreen , 2004 => :bracketpaste,
          1004 => :focusevents, 
        }
      end

      attr_reader :pty, :parser, :input

      def initialize(pty)
        @pty = pty
        @parser = Parser.new(self)
        @input = Input.new(self)
        @screen = Screen.new(self, pty.rows, pty.cols)
        @altscreen = Screen.new(self, pty.rows, pty.cols)
        @altscreen.skip_evict = true

        @cursor_style = :block_blink
        @on_bell = nil
        @on_window_title = nil
        @on_clipboard = nil

        setup_on_parse
      end

      def on_bell(&block)
        @on_bell = block
      end

      def on_window_title(&block)
        @on_window_title = block
      end
      
      def on_clipboard(&block)
        @on_clipboard = block
      end

      def ring
        @on_bell&.call
      end

      def screen
        modes[:altscreen] ? @altscreen : @screen
      end

      def setup_on_parse
        parser.on_parse do |action|
          case action.type
          when :execute then on_execute(action)
          when :print then on_print(action)
          when :csi_dispatch then on_csi_dispatch(action)
          when :dcs_passthrough then on_dcs_passthrough(action)
          when :escape_dispatch then on_escape(action)
          when :osc_dispatch then on_osc_dispatch(action)
          else
          end
        end
      end

      # 4.2 Control Characters
      def on_execute(action)
        case action.codepoint
        when SEQR["enq"]
        when SEQR["cr"] then screen.cursor.col = 0
        when SEQR["bel"] then ring
        when SEQR["bs"] then screen.cursor_backward(1)
        when SEQR["ht"] then screen.tabgoto
        when SEQR["lf"], SEQR["vt"], SEQR["ff"]
          modes[:lnm] ? screen.next_line : screen.index
        when SEQR["dc1"]
        when SEQR["dc2"]
        when SEQR["so"]
          # Invokes G1 character set into GL. G1 is designated by a select-character-set (SCS) sequence.
        when SEQR["si"]
          # Invoke G0 character set into GL. G0 is designated by a select-character-set sequence (SCS).
        when SEQR["can"] # canceled
        when SEQR["sub"]
          screen.print(SEQR["?"])
        end
      end

      def on_print(action)
        case parser.state
        when :ground
          screen.print(action.codepoint)
        end
      end

      # https://vt100.net/docs/vt220-rm/chapter4.html
      # 4.20 ANSI Mode Escape Sequences
      def on_escape(action)
        case action.intermediate_first&.chr
        when '#'
          case action.chr
          when '8' # 4.19 Tests and Adjustments (DECTST and DECALN)
          when '3' # 4.10.1 Double Height Line (DECDHL)
          when '4' # 
          when '5' # 4.10.2 Single-Width Line (DECSWL)
          when '6' # 4.10.3 Double-Width Line (DECDWL)
          end
        when '(', ')' # 4.4.1 Designating Hard Character Sets
        when nil
          case action.chr
          # reset
          when 'c' then reset_hard(action)
          when 'D' then screen.index
          when 'M' then screen.reverse_index
          when 'E' then screen.next_line
          when '7' # Save cursor (DECSC)
            @saved_cursor = Cursor.new
            @saved_cursor.row = screen.cursor.row
            @saved_cursor.col = screen.cursor.col
          when '8' # Restore cursor (DECRC)
            if @saved_cursor
              screen.cursor.row = @saved_cursor.row
              screen.cursor.col = @saved_cursor.col
            end
          when 'H' then screen.tabset
          when '=' then modes[:deckpam] = true
          when '>' then modes[:deckpam] = false
          end
        end
      end

      # VT200 compat, with extra support from
      # https://vt100.net/docs/vt510-rm/contents.html
      # https://invisible-island.net/xterm/ctlseqs/ctlseqs.html
      def on_csi_dispatch(action)
        case action.chr
        # Terminal modes: https://www.vt100.net/docs/vt220-rm/chapter4.html#T4-6
        when 'h' then set_mode(action)
        when 'l' then reset_mode(action)
        # Cursor positioning: 4.7
        when 'A' then screen.cursor_up(ensure_one(action.params[0]))
        when 'B' then screen.cursor_down(ensure_one(action.params[0]))
        when 'C' then screen.cursor_forward(ensure_one(action.params[0]))
        when 'D' then screen.cursor_backward(ensure_one(action.params[0]))
        # https://vt100.net/docs/vt510-rm/CHA.html
        when 'G' then screen.set_cursor(screen.cursor.row, ensure_one(action.params[0]) - 1)
        # https://vt100.net/docs/vt510-rm/VPA.html
        when 'd' then screen.set_cursor(ensure_one(action.params[0]) - 1, screen.cursor.col)
        when 'S' then screen.scroll_up(action.params[0] || 1)
        when 'T' then screen.scroll_down(action.params[0] || 1)
        when 'E'
          screen.cursor_down(ensure_one(action.params[0]))
          screen.cursor.col = 0
        when 'F'
          screen.cursor_up(ensure_one(action.params[0]))
          screen.cursor.col = 0
        when 'r' then screen.set_margins(action.params[0] || 0, action.params[1])
        when 'g' then screen.tabclear(action.params[0] == 3)
        # https://vt100.net/docs/vt510-rm/CUP.html
        # CUP is 1 indexed, so we need to subtract for our screen cursor, which is 0 indexed.
        when 'H', 'f' then screen.set_cursor(ensure_one(action.params[0]) - 1, ensure_one(action.params[1]) - 1)
        when 'm' then screen.sgr(action.params)
        # Editing
        when 'L' then screen.line_insert(ensure_one(action.params[0]))
        when 'M' then screen.line_delete(ensure_one(action.params[0]))
        when '@' then screen.insert_chars(ensure_one(action.params[0]))
        when 'P' then screen.delete_chars(ensure_one(action.params[0]))
        # Erasing
        when 'X' then screen.erase_char(ensure_one(action.params[0]))
        when 'K' then screen.erase_in_line(action.params[0] || 0, selective: action.private_marker_chr == '?')
        when 'J' then screen.erase_in_display(action.params[0] || 0, selective: action.private_marker_chr == '?')
        # Printing (ignore for now)
        when 'i' then nil
        # Reports
        when 'c' then report_attributes(action)
        when 'n' then report_status(action)
        # Style and graphics
        when 'q' # https://vt100.net/docs/vt510-rm/DECSCUSR.html
          if action.intermediate_first&.chr == ' '
            case action.param_first
            when 0, 1, nil
              @cursor_style = :block_blink
            when 2
              @cursor_style = :block
            when 3
              @cursor_style = :underline_blink
            when 4
              @cursor_style = :underline
            when 5
              @cursor_style = :bar_blink
            when 6
              @cursor_style = :bar
            end
          end
        # Reset
        when 'p'
          case action.intermediate_first&.chr
          when '!'
            soft_reset(action)
          when '"'
          when '$'
            request_mode(action)
          end
        end
      end

      def on_dcs_passthrough(action)
        case action.chr
        when "|" then nil # 4.15 User Defined Keys (DECUDK) (ignoring)
        when "{" then nil # 4.16 4.16 Down-Line-Loadable Character Set (ignoring)
        end
      end

      def on_osc_dispatch(action)
        code, text = action.content.split(";", 2)
        case code
        when '0', '2'
          @on_window_title&.call(text)          
          # set the window title
        when '8'
          # hyperlinks
        when '52'
          # clipboard
          @on_clipboard&.call(text)
        end
      end

      def set_mode(action)
        modemap = action.private_marker_chr == '?' ? dec_modemap : ansi_modemap

        action.params.each do |param|
          if mode = modemap[param]
            if hook = mode_hooks.dig(param, :before_enter)
              self.send(hook)
            end

            modes[mode] = true

            if hook = mode_hooks.dig(param, :after_enter)
              self.send(hook)
            end

          end
        end
      end

      def reset_mode(action)
        modemap = action.private_marker_chr == '?' ? dec_modemap : ansi_modemap

        action.params.each do |param|
          if mode = modemap[param]
            if hook = mode_hooks.dig(param, :before_exit)
              self.send(hook)
            end

            modes[mode] = false

            if hook = mode_hooks.dig(param, :after_exit)
              self.send(hook)
            end
          end
        end
      end

      def reset_hard(action)
        @modes = modes_initial
        scrollback = @screen.scrollback.dup
        @screen = Screen.new(self, pty.rows, pty.cols)
        @screen.scrollback = scrollback
        @parser.reset
      end

      def soft_reset(action)
        @modes[:irm] = false
        @modes[:decom] = false
        @modes[:decckm] = false
        @modes[:kam] = false
        @modes[:dectcem] = true
        screen.reset_style
        screen.cursor.row = 0
        screen.cursor.col = 0
      end

      def report_attributes(action)
        case action.private_marker_chr
        when nil
          case action.param_first
          when nil, 0
            # send 
            # SEQ["CSI ? 62 c"]
          end
        when '>'
          case action.param_first
          when nil, 0
            # send
            #SEQ["CSI > 1 ; 1 ; 0 c"]
          end
        end
      end

      def report_status(action)
        case action.param_first
        when 5
          # lol?
          # send
          # SEQ["CSI 0 n"]
        when 6
          # send
          # SEQ["CSI #{screen.cursor.row + 1} ; #{[screen.cursor.col, screen.cols - 1].min + 1} R"]
        end
      end

      def request_mode(action)
        param = action.param_first
        pc = action.private_marker_chr
        modemap = pc == '?' ? dec_modemap : ansi_modemap
    
        if mode = modemap[param]
          ret = modes[mode] ? 1 : 2
        else
          ret = 0
        end
        # send
        # SEQ["CSI #{pc} #{param} ; #{ret} $ y"]
      end

      def clear_alt_screen
        @altscreen = Screen.new(self, pty.rows, pty.cols)
        @altscreen.skip_evict = true
      end

      def prepare_alt_screen
        cursor = @screen.cursor
        clear_alt_screen
        @altscreen.cursor.row = cursor.row
        @altscreen.cursor.col = cursor.col
      end

      private
      # From https://vt100.net/docs/vt220-rm/chapter4.html
      # NOTE: If you select no parameter or a parameter value of 0, the terminal assumes the parameter equals 1.
      def ensure_one(param)
        case param
        when nil, 0 then 1
        else
          param
        end
      end
    end
  end
end
