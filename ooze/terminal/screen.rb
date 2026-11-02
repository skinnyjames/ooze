require_relative "./style"
require_relative "./screen/line"

module Ooze
  module Terminal
    Cursor = Struct.new(:row, :col)

    # Public: Represents a Terminal Screen
    #         Holds logic and buffer for all screen interaction
    # 
    # # Array of Unique styles
    # @styles = [Terminal::Style, Terminal::Style]
    # 
    # # Hash where the keys are frozen style snapshots
    # #        and the values are indexes into @styles
    # @stylemap = { style => 0, other_style => 1 }
    # 
    # Styles with the same properties share a hash entry
    class Screen
      attr_accessor :current_style_id, :margin_top, :margin_bottom,
                    :current_line_width, :cursor, :scrollback, :skip_evict, 
                    :max_scrollback

      attr_reader :session, :rows, :cols, :cursor, :styles, :stylemap, :lines, :current_style,
                  :tabstops, :default_style_id

      def initialize(session, rows, cols)
        @session = session
        @rows = rows
        @cols = cols

        @cursor = Cursor.new(0, 0)
        @tabstops = {}
        @margin_top = 0
        @margin_bottom = rows - 1

        # Scrollback vars
        @scrollback = []
        @skip_evict = false
        @on_evicted = nil
        @max_scrollback = 10_000

        # Misc state
        @last_codepoint = nil

        # An array of unique style objects (index is the style id)
        @styles = []
        # A lookup of styles => @styles index
        @stylemap = {}
        @lines = Array.new(rows) do
          Line.new(cols)
        end

        @current_style = Style.new
        @current_style_id = intern(@current_style)
        @default_style_id = @current_style_id

        setup_tabstops
      end

      # Public: Sets a callback for each evicted line as runs
      #
      # block - callback that will be called with 
      #         Array(Hash(chars: String, style: Ooze::Terminal::Style))
      #         
      # Returns nothing
      def on_evicted(&block)
        @on_evicted = block
      end

      # Public: Yields a string of consecutive chars with the same style.
      #         If the line is empty, yield :newline
      # 
      # block - callback that will be called with 
      #         Array(String, Ooze::Terminal::Style) | Symbol
      #
      # Returns nothing
      def runs(&block)
        lines.each do |line|
          runs = line.runs(default_style_id)
          runs.each do |run|
            if run.empty?
              yield :newline
            else
              yield [run[0], styles[run[1]]]
            end
          end

          yield :newline
        end
      end

      # Public: Reset all properties on the active style
      # 
      # Returns nothing
      def reset_style
        @current_style.reset
        @current_style_id = intern(@current_style)
      end

      # Internal: Initializes tabstops at every 8th column
      # 
      # Returns nothing
      def setup_tabstops
        (0...cols).each do |i|
          if i % 8 == 0
            @tabstops[i] = true
          end
        end
      end

      # Public: Returns current line under cursor
      # 
      # Returns Ooze::Terminal::Line
      def current_line
        @lines[@cursor.row]
      end

      # Public: Applys SGR parameters (ps) to current style.
      #         If new style combination is not cached, cache it.
      #
      # ps - an array of CSI/SGR parameters (Array(Integer))  
      #
      # Returns nothing
      def sgr(ps)
        @current_style.sgr(ps)
        @current_style_id = intern(@current_style)
      end

      # Public: Indexes an style with a unique combination of properties.
      #         If the style properties are already cached, return that instead.
      #         
      # style - a Ooze::Terminal::Style
      # 
      # Returns a style id (Integer)
      def intern(style)
        id = stylemap[style]
        return id if id
  
        snap = style.snapshot.freeze
        styles << snap
        stylemap[snap] = styles.size - 1
      end

      # Internal: Evicts a line of runs into scrollback.
      #           if Line#skip_evict is true, this will be skipped.
      #           if Line#on_evicted callback is set, it will be called.
      # 
      # line - a Ooze::Terminal::Line
      # 
      # Returns nothing
      def evict(line)
        return if skip_evict

        runs = line.runs(default_style_id).map do |run|
          { chars: run[0], style: styles[run[1]]}
        end

        if runs.empty?
          to_evict = [{ chars: "\n", style: styles[default_style_id] }]
        else
          if runs[-1] && !runs[-1][:chars].empty?
            runs[-1][:chars] = runs[-1][:chars] + "\n"
          end
          to_evict = runs
        end

        @on_evicted&.call(to_evict)
        scrollback.concat to_evict
        scrollback.shift(scrollback.size - @max_scrollback) if scrollback.size > @max_scrollback
      end

      def set_cursor(row, col)
        return set_cursor!(row, col) unless session.modes[:decom]

        @cursor.row = [[row + margin_top, margin_bottom].min, margin_top].max
        @cursor.col = [col, cols - 1].min 
      end

      # Public: index moves the cursor down one line in the same column.
      #         If the cursor is at the bottom margin, the screen performs a scroll-up.
      #         https://vt100.net/docs/vt220-rm/chapter4.html
      # 
      # Returns nothing
      def index
        if @cursor.row == margin_bottom
          scroll_up
        else
          @cursor.row += 1 unless @cursor.row >= rows - 1
        end
      end

      # Public: Scroll the screen up (times) times.
      #         Lines at the top will be evicted.
      # 
      # times - number of times to scroll up (Integer)
      # 
      # Returns nothing
      def scroll_up(times = 1)
        times.times do
          line = @lines.delete_at(margin_top)
          evict(line) if margin_top.zero?
          line.clear
          @lines.insert(margin_bottom, line)
        end
      end

      # Public: index moves the cursor up one line in the same column.
      #         If the cursor is at the top margin, the screen performs a scroll-down.
      #         https://vt100.net/docs/vt220-rm/chapter4.html
      #
      # Returns nothing
      def reverse_index
        if @cursor.row == margin_top
          scroll_down
        else
          @cursor.row -= 1 unless @cursor.row - 1 < 0
        end
      end

      # Public: Scroll down (times) times
      #         Lines at the bottom will be deleted.
      # 
      # times - the number of times to scroll down
      # 
      # Returns nothing
      def scroll_down(times = 1)
        times.times do
          @lines.delete_at(margin_bottom)
          @lines.insert(margin_top, Line.new(cols))
        end
      end

      # Public: Indexes the screen and sets the cursor 
      #         to the beginning of the line
      # 
      # Returns nothing
      def next_line
        index

        @cursor.col = 0
      end

      # Public: Moves cursor to the next (times) tabstop
      #         If no more tabstops are present, moves the cursor
      #         to the edge of the screen. 
      #
      # times - times to move the cursor
      # 
      # Returns nothing
      def tabgoto(times = 1)
        stops = @tabstops.keys.sort

        times.times do
          stopped = stops.find do |stop|
            stop > @cursor.col
          end

          @cursor.col = stopped || cols - 1
        end
      end

      # Public: Moves cursor to the previous (times) tabstop
      #         If no more tabstops are present, moves the cursor
      #         to the beginning of the screen. 
      #
      # times - times to move the cursor
      # 
      # Returns nothing
      def tabback(times = 1)
        stops = @tabstops.keys.sort

        times.times do
          stopped = stops.reverse.find do |stop|
            stop < @cursor.col
          end

          @cursor.col = stopped || 0
        end
      end

      # Public: Sets a tabstop at cursor position
      # 
      # Returns nothing
      def tabset
        @tabstops[@cursor.col] = true
      end

      # Public: Clears tabstop at cursor position
      #         if (all) is true, clear all tabstops
      #         
      # all - clear all tabstops (Boolean)
      # 
      # Returns nothing
      def tabclear(all = false)
        if all
          @tabstops.clear
          return
        end

        @tabstops.delete(@cursor.col)
      end

      # https://vt100.net/docs/vt220-rm/chapter4.html
      # 4.10 Line Attributes
      # No-Op for now, how dumb.

      # Public: Inserts (count) lines at the cursor. 
      #        If fewer than (count) lines remain from the current line to the end of the scrolling region, 
      #        the number of lines inserted is the lesser number. 
      #        Lines within the scrolling region at and below the cursor move down.
      #        Lines moved past the bottom margin are lost. The cursor is reset to the first column. 
      #        This sequence is ignored when the cursor is outside the scrolling region.
      #
      # count - the number of lines to insert
      #
      # Returns nothing
      def line_insert(count)
        return if @cursor.row > margin_bottom || @cursor.row < margin_top

        count = (margin_bottom + 1) - @cursor.row > count ? count : (margin_bottom + 1) - @cursor.row

        # insert the lines
        count.times do
          @lines.insert(@cursor.row, Line.new(cols))
        end

        # truncate extra rows
        count.times do
          @lines.delete_at(margin_bottom + 1)
        end

        # reset the cursor
        @cursor.col = 0
      end

      # Public: Deletes Pn lines starting at the line with the cursor.
      #         If fewer than Pn lines remain from the current line to the end of the scrolling region, 
      #         the number of lines deleted is the lesser number. 
      #         As lines are deleted, lines within the scrolling region and below the cursor move up, and 
      #         blank lines are added at the bottom of the scrolling region. The cursor is reset to the first column. 
      #         This sequence is ignored when the cursor is outside the scrolling region.
      #
      # count - the number of lines to delete
      #
      # Returns nothing
      def line_delete(count)
        return if @cursor.row > margin_bottom || @cursor.row < margin_top

        count = (margin_bottom + 1) - @cursor.row > count ? count : (margin_bottom + 1) - @cursor.row

        @lines[@cursor.row, count] = []

        count.times do
          @lines.insert(margin_bottom + 1 - count, Line.new(cols))
        end

        @cursor.col = 0
      end

      # TODO: Rename method
      # Public: Inserts a space (count) times at cursor position
      # 
      # count - tiems to insert the space
      # 
      # Returns nothing
      def insert_chars(count)
        return if @cursor.row > margin_bottom || @cursor.row < margin_top

        count = 1 if count.zero?

        count.times do
          current_line.insert(@cursor.col, SEQR["sp"], @default_style_id)
        end
      end

      # Public: Delete chars under cursor (count) times
      #         Shifts the remaining chars left and appends line with spaces
      #         
      # count - times to delete at cursor
      def delete_chars(count)
        count = [count, cols - @cursor.col].min

        count.times do
          current_line.delete(@cursor.col)

          current_line.codepoints << SEQR["sp"]
          current_line.widths << 1
          current_line.attrs << @default_style_id
        end
      end

      # Public: Prints last recieved codepoint (count) times
      # 
      # count - times to print the codepoint
      # 
      # Returns nothing
      def repeat_last_char(count)
        return unless @last_codepoint

        count.times do 
          print(@last_codepoint)
        end
      end

      # 4.1.2 Erasing
      # Public: Erases characters at the cursor position and the next (count)-1 characters. 
      #         A parameter of 0 or 1 erases a single character. 
      #         Character attributes are set to normal. No reformatting of data on the line occurs. 
      #         The cursor remains in the same position.
      # 
      # count - times to erase the char
      # 
      # Returns nothing
      def erase_char(count)
        count = count.zero? ? 1 : count

        count.times do |a|
          i = [@cursor.col + a, cols - 1].min

          current_line.blank(i, @default_style_id, blank_nil: true)
        end
      end

      # Public: Erases parts of the line depending on (mode).
      #         Mode = 0 Erases from the cursor to the end of the line, including the cursor position.
      #                  Line attribute is not affected.
      #         Mode = 1 Erases from the beginning of the line to the cursor, 
      #                 including the cursor position. Line attribute is not affected.
      #         Mode = 2 Erases the complete line.
      # 
      # mode - the erase mode (Integer)
      # kwargs -
      #   selective: skip erase if true
      #
      # Returns nothing
      def erase_in_line(mode, line: current_line, selective: false)
        return if selective # Not handling (Selective Erase In Line (DECSEL))

        col = [@cursor.col, cols - 1].min
        ranges = { 0 => (col...cols), 1 => (0..col), 2 => (0...cols) }
      
        # ignore bad modes
        if range = ranges[mode]
          range.each do |i|
            line.blank(i, @default_style_id, blank_nil: true)
          end

          if mode == 0 || mode == 2
            line.wrapped = false
          end
        end
      end

      # Public: Erases parts of the display depending on (mode)
      #         Mode = 0 Erases from the cursor to the end of the screen, 
      #                  including the cursor position. Line attribute 
      #                  becomes single-height, single-width for all completely erased lines. 
      #         Mode = 1 Erases from the beginning of the screen to the cursor, 
      #                  including the cursor position. Line attribute 
      #                  becomes single-height, single-width for all completely erased lines.
      #         Mode = 2 Erases the complete display. All lines are erased and changed to single-width. The cursor does not move.
      #         
      # mode - the erase mode (Integer)
      # kwargs -
      #   selective: skips erase if true
      #   
      # Returns nothing
      def erase_in_display(mode, selective: false)
        return if selective # Not Handling (Selective Erase In Display (DECSED))

        ranges = { 0 => (@cursor.row + 1...rows), 1 => (0...@cursor.row), 2 => (0...rows) }

        # erase the line
        if range = ranges[mode]
          range.each do |row|
            line = @lines[row]
            erase_in_line(2, line: line)
          end
        end

        erase_in_line(mode)
      end

      # 4.13 Scrolling margins
      # Public: Set margins/scroll region.  When margins are set, 
      #         indexing/scroll/line insert is restricted to the screen subset
      # 
      # top - the top margin (clamped to screen top)
      # bottom - the bottom margin (clamped to screen bottom)
      # 
      # Returns nothing
      def set_margins(top, bottom)
        t = top
        b = bottom
        t = 1 if top.nil? || top.zero?
        b = rows if bottom.nil? || bottom.zero?
        b = [b, rows].min

        t -= 1
        b -= 1

        return if t >= b

        self.margin_top = t
        self.margin_bottom = b
        @cursor.row = 0
        @cursor.col = 0
      end

      # Public: Resets margins to screen borders
      # 
      # Returns nothing
      def reset_margins
        self.margin_top = 0
        self.margin_bottom = rows - 1
      end

      # Public: Moves the cursor up (count) lines in the same column. 
      #         The cursor stops at the top margin.
      #
      # count - the rows to move up
      # 
      # Returns nothing
      def cursor_up(count)
        top = @cursor.row >= margin_top ? margin_top : 0
        new_row = @cursor.row - count
        @cursor.row = [top, new_row].max
      end

      # Public: Moves the cursor down (count) lines in the same column. 
      #         The cursor stops at the bottom margin.
      #
      # count - the rows to move down
      # 
      # Returns nothing
      def cursor_down(count)
        bottom = @cursor.row <= margin_bottom ? margin_bottom : rows - 1
        new_row = @cursor.row + count 
        @cursor.row = [new_row, bottom].min
      end

      # Public: Moves the cursor right (count) columns. 
      #         The cursor stops at the right margin.
      #
      # count - the columns to move forward
      # 
      # Returns nothing
      def cursor_forward(count)
        new_col = @cursor.col + count
        offset = session.modes[:decawm] ? 0 : 1
        col_with_offset = new_col > cols - offset ? cols - offset : new_col
        @cursor.col = [cols - 1, col_with_offset].min
      end

      # Public: Moves the cursor left (count) columns. 
      #         The cursor stops at the left margin.
      #         Note: if autowrap + reverse wrap is set, the cursor will 
      #         backward traverse soft wrapped lines
      #
      # count - the columns to move backward
      # 
      # Returns nothing
      def cursor_backward(count)
        reverse_wrap = session.modes[:decawm] && session.modes[:xtrevwrap]

        count -= 1 if @cursor.col >= cols && reverse_wrap
        @cursor.col = [@cursor.col, cols - 1].min   # leave pending-wrap position

        count.times do
          # move up and back if wrapped and reverse wrap is on
          if @cursor.col.zero? && reverse_wrap
            prev_row = @cursor.row - 1
            if prev_row >= margin_top && @lines[prev_row]&.wrapped 
              @cursor.row = prev_row
              @cursor.col = cols - 1
            else
              break
            end
          elsif @cursor.col > 0
            @cursor.col -= 1
          else
            break
          end
        end
      end

      # Public: Sets the cursor to (row, col).
      #         Clamps to screen borders.
      # 
      # row - the row to set (Integer)
      # col - the col to set (Integer)
      # 
      # Returns nothing
      def set_cursor!(row, col)
        @cursor.row = clamp(row, 0, rows - 1)
        @cursor.col = clamp(col, 0, cols - 1) 
      end

      # TODO: UTF-8 Needs to handle grapheme breaks.
      #       The parser can emit ZWJ or other (control) chars.
      #       ref: deps/mruby-utf8proc/src/utf8proc.h#644
      # 
      # Public: Prints a codepoint to the screen.
      #         If autowrap is on and in pending wrap position,
      #         prints on the next line. Advances the cursor.
      # 
      # codepoint - the codepoint to print
      # 
      # Returns nothing.
      def print(codepoint)
        decawm = session.modes[:decawm]
        @last_codepoint = codepoint
        width = codepoint < ASCII_CODE_TABLE[:del] ? 1 : session.width(codepoint)

        # wrap pending and autowrap is on, move the cursor down
        if decawm && @cursor.col + width > cols
          @lines[@cursor.row].wrapped = true
          @cursor.col = 0
          index
        end
  
        line = @lines[@cursor.row]

        if session.modes[:irm]
          line.insert(@cursor.col, codepoint, current_style_id, width)
        else
          col = clamp(@cursor.col, 0, cols - width)
          line.replace(col, codepoint, current_style_id, width)
        end

        # advance cursor
        new_col = @cursor.col + width
        offset = decawm ? 0 : 1
        col_with_offset = new_col > cols - offset ? cols - offset : new_col
        @cursor.col = col_with_offset
      end

      # Public: Like cursor_forward but can move into the 
      #         right margin (pending wrap) position
      #
      # count - times to move the cursor forward (Integer)
      # autowrap - wheither to move to the pending wrap position (Boolean)
      # 
      # Returns nothin
      def advance(count, autowrap = false)
        new_col = @cursor.col + count
        offset = autowrap ? 0 : 1
        col_with_offset = new_col > cols - offset ? cols - offset : new_col
        @cursor.col = col_with_offset
      end

      # Public: Sets the whole screen to 'E'.
      #         (used for diagnostics.)
      #
      # Returns nothing
      def alignment
        @lines = Array.new(rows) do
          line = Line.new(cols)
          line.codepoints = ['E'.ord] * cols
          line.attrs = [default_style_id] * cols
          line 
        end
      end

      private

      # Public: Clamps value to min/max
      # 
      # value - the value to clamp
      # min - the minium possible clamp value
      # max - the maximum possible clamp value
      def clamp(value, min, max)
        return min if value < min
        return max if value > max
        value
      end
    end
  end
end
