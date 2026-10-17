module Ooze
  module Terminal
    class Session
      def self.spawn(rows, cols, shell = "bash")
        shell = ENV["SHELL"] || shell
        token = Sysrandom.base64
        ENV["OOZE_TOKEN"] = token
        
        shell_dir = File.expand_path(ENV.fetch("OOZE_SHELL_DIR", "assets/shell"))
        ENV["PATH"] = "#{ENV["PATH"]}:#{shell_dir}"

        pty = PTY.spawn(shell, rows, cols)
        new(pty, secret: token)
      end

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
      # 
      # Xterm specific things
      # XTREVWRAP (Reverse Wrap) # https://github.com/ThomasDickey/esctest2/blob/master/esctest/tests/bs.py#L174
      def modes
        @modes ||= modes_initial
      end

      # https://vt100.net/docs/vt510-rm/DECRQM.html
      PERMANENTLY_RESET_ANSI_MODES = [1, 5, 7, 10, 11, 13, 14, 15, 16, 17, 18, 19]
      PERMANENTLY_RESET_DEC_MODES = [60]

      def modes_initial
        {
          kam: false, irm: false, srm: false,
          lnm: false, decckm: false, decanm: true,
          deccolm: false, decsclm: false, decscnm: false,
          decom: false, decawm: true, decarm: true, decpff: false,
          decpex: false, dectcem: true, deckpam: false,
          decnrcm: false, altscreen: false, bracketpaste: false,
          focusevents: false,
          xtrevwrap: false,
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
          47 => :altscreen, 66 => :deckpam, 1047 => :altscreen , 
          2004 => :bracketpaste, 1004 => :focusevents,
          45 => :xtrevwrap
        }
      end

      attr_accessor :ambiguous_width, :secret
      attr_reader :pty, :parser, :input, :charset

      PTY_BUFFER_SIZE = 1024

      def initialize(pty, secret: nil)
        @pty = pty
        rows, cols = pty.size
  
        @parser = Parser.new(self)
        @input = Input.new(self)
        @screen = Screen.new(self, rows, cols)
        @altscreen = Screen.new(self, rows, cols)
        @altscreen.skip_evict = true

        @secret = secret
        @on_plugin = nil

        @ambiguous_width = 1
        @charset = :ascii
        @cursor_style = :block_blink

        @on_bell = nil
        @on_window_title = nil
        @on_clipboard = nil

        @inbox = ""
        @inbox_pos = 0
        @inbox_max = 4 * 1024 * 1024

        setup_on_parse
      end

      # Public: Writes (content) directly to the PTY
      # 
      # content - content to write (UTF-8 encoded String)
      # 
      # Returns nothing
      def write(content)
        pty.io.write(content)
      end

      # Public: Reads from the pty for (timeout) seconds until inbox is at @inbox_max
      #         Returns early if nothing is available to be read
      # 
      # timeout - seconds to read from pty (Float)
      # budget - number of bytes to parse after draining the pty 
      # 
      # Returns number of bytes read (Integer)
      def read(timeout = 0.01, budget = 64 * 1024)
        timer = Hokusai::Util::Timer.new
        size = 0
        begin
          while !inbox_at_capacity? && !timer.elapsed(timeout)
            message = pty.io.sysread(PTY_BUFFER_SIZE)
            size += message.bytesize
            @inbox << message
          end
  
          size
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::EIO, EOFError
          size
        end

        if inbox_capacity > 0
          cap = inbox_capacity < budget ? inbox_capacity : budget
          parser.parse(@inbox.byteslice(@inbox_pos, cap).freeze)
          @inbox_pos += cap

          if @inbox_pos == @inbox.bytesize
            @inbox = ""
            @inbox_pos = 0
          end
        end

        size
      end

      def inbox_at_capacity?
        inbox_capacity >= @inbox_max
      end

      def inbox_capacity
        @inbox.bytesize - @inbox_pos
      end

      # Public: Reads available bytes from pty
      # 
      # timeout - seconds to read from pty (Float)
      # 
      # Returns number of bytes read (Integer)
      def read_soon(timeout)
        if IO.select([pty.io], nil, nil, timeout)
          read
        else
          0
        end
      end

      # Public: Returns the width of a given (codepoint)
      #         Includes a fast path for ascii
      # 
      # codepoint - codepoint (Integer)
      # 
      # Returns width (Integer)
      def width(codepoint)
        codepoint < ASCII_CODE_TABLE[:del] ? 1 : codepoint.charwidth(ambiguous_width)
      end

      # Public: Sets the bel sequence callback
      # 
      # block - a callback to call on bel
      # 
      # Returns nothing
      def on_bell(&block)
        @on_bell = block
      end

      # Public: Sets the OSC window title callback
      # 
      # block - callback that will be called with the new window title
      # 
      # Returns nothing
      def on_window_title(&block)
        @on_window_title = block
      end
      
      # Public: Callback that is called with the clipboard text
      # 
      # block - callback
      # 
      # Returns nothing
      def on_clipboard(&block)
        @on_clipboard = block
      end

      # Public: Triggers bell callback
      # 
      # Returns nothing
      def ring
        @on_bell&.call
      end

      # Public: Sets the callback for Ooze specific OSC plugin sequence,
      #         See: assets/shell/oz
      # 
      # block - the plugin callback
      # 
      # Examples
      # 
      #   session.on_plugin do |command, id, plugin_name, current_directory, on_reply, on_cancel|
      #     case command
      #     when :start   # called on plugin initialize
      #     when :data    # called on data being piped to the script
      #     when :done    # called on no more data
      #     when :closed  # called when plugin is closed (returns a reply or cancels)
      #     when :cancel  # called when command is canceled
      #     when :error   # reserved for shell errors (unused)
      #     end
      #   end
      #
      # Returns nothing
      def on_plugin(&block)
        @on_plugin = block
      end

      # Public: Returns currently active screen
      # 
      # Returns Ooze::Terminal::Screen
      def screen
        modes[:altscreen] ? @altscreen : @screen
      end

      def setup_on_parse
        parser.on_parse do |action|
          case action.type
          when :execute then on_execute(action)
          # when :print then on_print(action)
          # when :print_aggregate then on_print_aggregate(action)
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
        when ASCII_CODE_TABLE[:enq]
        when ASCII_CODE_TABLE[:cr] then screen.cursor.col = 0
        when ASCII_CODE_TABLE[:bel] then ring
        when ASCII_CODE_TABLE[:bs] then screen.cursor_backward(1)
        when ASCII_CODE_TABLE[:ht] then screen.tabgoto
        when ASCII_CODE_TABLE[:lf], ASCII_CODE_TABLE[:vt], ASCII_CODE_TABLE[:ff]
          modes[:lnm] ? screen.next_line : screen.index
        when ASCII_CODE_TABLE[:dc1]
        when ASCII_CODE_TABLE[:dc2]
        when ASCII_CODE_TABLE[:so]
          # Invokes G1 character set into GL. G1 is designated by a select-character-set (SCS) sequence.
        when ASCII_CODE_TABLE[:si]
          # Invoke G0 character set into GL. G0 is designated by a select-character-set sequence (SCS).
        when ASCII_CODE_TABLE[:can] # canceled
        when ASCII_CODE_TABLE[:sub]
          screen.print(SEQR["?"])
        end
      end

      # Public: Prints a codepoint to the screen.
      #         If charset is not ascii, (such as dec special graphics) uses the charset for codepoint
      #         
      # Returns nothing
      def print(codepoint)
        codepoint = @charset == :ascii ? codepoint : SEQ.with_charset(codepoint, @charset)
        screen.print(codepoint)
      end

      # https://vt100.net/docs/vt220-rm/chapter4.html
      # 4.20 ANSI Mode Escape Sequences
      # Internal: Handles escape esc sequences
      def on_escape(action)
        case action.intermediate_first&.chr
        when '#'
          case action.chr
          when '8' # 4.19 Tests and Adjustments (DECTST and DECALN)
            screen.alignment
            screen.set_margins(0, nil)
            screen.set_cursor!(0, 0)
          when '3' # 4.10.1 Double Height Line (DECDHL)
          when '4' # 
          when '5' # 4.10.2 Single-Width Line (DECSWL)
          when '6' # 4.10.3 Double-Width Line (DECDWL)
          end
        when '('  # 4.4.1 Designating Hard Character Sets
          case action.chr
          when '0' then @charset = :dec_graphics # activate DEC special graphics
          when 'B' then @charset = :ascii # switch to ascii
          end
        when nil
          case action.chr
          # reset
          when 'c' then reset_hard(action)
          when 'D' then screen.index
          when 'M' then screen.reverse_index
          when 'E' then screen.next_line
          when '7' then save_cursor 
          when '8' then restore_cursor
          when 'H' then screen.tabset
          when '=' then modes[:deckpam] = true
          when '>' then modes[:deckpam] = false
          end
        end
      end

      # VT200 compat, with extra support from
      # https://vt100.net/docs/vt510-rm/contents.html
      # https://invisible-island.net/xterm/ctlseqs/ctlseqs.html
      # Internal: Handles CSI esc sequences
      def on_csi_dispatch(action)
        case action.chr
        # Terminal modes: https://www.vt100.net/docs/vt220-rm/chapter4.html#T4-6
        when 'h' then set_mode(action)
        when 'l' then reset_mode(action)
        when 'b' then screen.repeat_last_char(ensure_one(action.params[0]))
        # Cursor positioning: 4.7
        when 'A' then screen.cursor_up(ensure_one(action.params[0]))
        when 'B' then screen.cursor_down(ensure_one(action.params[0]))
        when 'C', 'a' then screen.cursor_forward(ensure_one(action.params[0]))
        when 'D' then screen.cursor_backward(ensure_one(action.params[0]))
        # https://vt100.net/docs/vt510-rm/VPR.html
        when 'e' then screen.set_cursor!(screen.cursor.row + ensure_one(action.params[0]), screen.cursor.col)
        # https://vt100.net/docs/vt510-rm/CHA.html
        when 'G' then screen.set_cursor!(screen.cursor.row, ensure_one(action.params[0]) - 1)
        # https://vt100.net/docs/vt510-rm/CUP.html
        # CUP is 1 indexed, so we need to subtract for our screen cursor, which is 0 indexed.
        when 'H', 'f' then screen.set_cursor(ensure_one(action.params[0]) - 1, ensure_one(action.params[1]) - 1)
        # https://vt100.net/docs/vt510-rm/VPA.html
        when 'd' then screen.set_cursor!(ensure_one(action.params[0]) - 1, screen.cursor.col)
        # https://vt100.net/docs/vt510-rm/HPA.html
        when '`' then screen.set_cursor!(screen.cursor.row, ensure_one(action.params[0]) - 1)
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
        when 'I' then screen.tabgoto(ensure_one(action.params[0]))
        when 'Z' then screen.tabback(ensure_one(action.params[0]))
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
        # save restore cursor
        when 's' then save_cursor if action.private_marker_chr.nil?
        when 'u' then restore_cursor if action.private_marker_chr.nil?
        # Reports
        when 'c' then report_attributes(action)
        when 'n' then report_status(action)
        when 't' then report_window(action)
        when 'y' then request_checksum(action)
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
        when '00z3'
          # ooze handler
          # request shape: "00z3;<token>;<cmd>;<correlationid>;<plugin>;<base64 payload>"
          token, command, id, plugin_name, payload = text.split(";", 5)
          return unless token == secret

          on_cancel = Proc.new do
            response = "00z3;cancel;#{id}"
            input.write OSC + response.codepoints + SEQ["bel"]

            @on_plugin&.call(:closed, id)
          end

          on_reply = Proc.new do |text|
            encoded = b64_encode(text)
            response = "00z3;reply;#{id};#{encoded}"
            input.write OSC + response.codepoints + SEQ["bel"]

            @on_plugin&.call(:closed, id)
          end

          case command
          when "start"
            @on_plugin&.call(:start, id, plugin_name, b64_decode(payload.to_s), on_reply, on_cancel)
          when "data"
            @on_plugin&.call(:data, id, b64_decode(payload.to_s))
          when "done"
            @on_plugin&.call(:done, id)
          when "cancel"
            @on_plugin&.call(:cancel, id)
          when "error"
            @on_plugin&.call(:error, id)
          end
        end
      end

      # Internal: Sets the ansi or dec mode
      # 
      # action - a Ooze::Terminal::Parser::Action
      # 
      # Returns nothing
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

      # Internal: Resets the ansi or dec mode
      # 
      # action - a Ooze::Terminal::Parser::Action
      # 
      # Returns nothing
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

      # Internal: Resets all properties on session
      #         Starts a new screen and migrates scrollback
      def reset_hard(action)
        @modes = modes_initial
        scrollback = @screen.scrollback.dup
        rows, cols = pty.size
        @saved_cursors = {}
        @screen = Screen.new(self, rows, cols)
        @screen.scrollback = scrollback
        clear_alt_screen
        @parser.reset
        @charset = :ascii
      end

      # https://vt100.net/docs/vt510-rm/DECSTR.html
      # Internal: Resets a specified modes, margins, active style, and cursors
      def soft_reset(action)
        @modes[:irm] = false
        @modes[:decom] = false
        @modes[:decckm] = false
        @modes[:kam] = false
        @modes[:dectcem] = true
        @modes[:xtrevwrap] = false
        screen.reset_margins
        screen.reset_style

        @saved_cursors = { true => { row: 0, col: 0, origin_mode: false }, false => { row: 0, col: 0, origin_mode: false } }
        @charset = :ascii
      end

      def report_attributes(action)
        case action.private_marker_chr
        when nil
          case action.param_first
          when nil, 0
            input.write SEQ["CSI ? 62 c"]
          end
        when '>'
          case action.param_first
          when nil, 0
            input.write SEQ["CSI > 1 ; 1 ; 0 c"]
          end
        end
      end

      def report_status(action)
        case action.param_first
        when 5
          # lol?
          input.write SEQ["CSI 0 n"]
        when 6
          input.write SEQ["CSI #{screen.cursor.row + 1} ; #{[screen.cursor.col, screen.cols - 1].min + 1} R"]
        end
      end

      def report_window(action)
        case action.param_first
        when 18
          input.write SEQ["CSI 8 ; #{screen.rows} ; #{screen.cols} t"]
        end
      end

      def request_mode(action)
        param = action.param_first
        pc = action.private_marker_chr
        modemap = pc == '?' ? dec_modemap : ansi_modemap
        reset = pc == '?' ? PERMANENTLY_RESET_DEC_MODES : PERMANENTLY_RESET_ANSI_MODES

        if mode = modemap[param]
          ret = modes[mode] ? 1 : 2
        elsif reset.include?(param)
          ret = 4
        else
          ret = 0
        end
 
        input.write SEQ["CSI #{pc} #{param} ; #{ret} $ y"]
      end

      # https://vt100.net/docs/vt510-rm/DECRQCRA.html
      # Esctest relies on this
      # Algorithim here: https://github.com/ThomasDickey/esctest2/blob/2798f12149a19c3295e9b4853ab2da4b2eff1b2b/esctest/escutil.py#L237-L307
      def request_checksum(action)
        return unless action.intermediate_first&.chr == '*'
        pid, pp, top, left, bottom, right = action.params

        bottom = screen.rows if bottom.nil? || bottom.zero?
        right = screen.cols if right.nil? || right.zero?

        # clamp and zero index
        top = ensure_one(top) - 1
        left = ensure_one(left) - 1
        right = [screen.cols, right].min - 1
        bottom = [screen.rows, bottom].min - 1        

        sum = 0
        (top..bottom).each do |row|
          (left..right).each do |col|
            cp = screen.lines[row].codepoints[col]
            sum += (cp.nil? || cp == :continue) ? 0x20 : cp
          end
        end

        checksum = format('%04X', -(sum) & 0xFFFF)
        input.write DCS + SEQ["#{pid} ! ~"] + checksum.codepoints + ST
      end

      def clear_alt_screen
        rows, cols = pty.size
        @altscreen = Screen.new(self, rows, cols)
        @altscreen.skip_evict = true
        @saved_cursors&.delete(true)
      end

      def prepare_alt_screen
        cursor = @screen.cursor
        clear_alt_screen
        @altscreen.cursor.row = cursor.row
        @altscreen.cursor.col = cursor.col
      end

      def save_cursor
        @saved_cursors ||= {}
        @saved_cursors[modes[:altscreen]] = { row: screen.cursor.row, col: screen.cursor.col, origin_mode: modes[:decom] }
      end

      def restore_cursor
        @saved_cursors ||= {}
        unless data = @saved_cursors[modes[:altscreen]]
          return
        end

        screen.cursor.row = data[:row]
        screen.cursor.col = data[:col]
        modes[:decom] = data[:origin_mode]
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

      def b64_decode(str)
        str.unpack("m").first.to_s
      end

      def b64_encode(str)
        [str].pack("m").delete("\n")
      end
    end
  end
end
