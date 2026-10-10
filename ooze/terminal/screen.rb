require_relative "./style"

module Ooze
  module Terminal
    # Public: A line (row) on the screen
    # #
    # Representation by logical char
    # #
    #                cols | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 
    #           line text | f | 👧|:co| o |   | b | a | r |
    #   attrs (style ids) | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 1 |
    #              widths | 1 | 2 | * | 1 | 1 | 1 | 1 | 1 |
    # #
    # Representation by rendered column (wide chars)
    #   * represents continuation of wide char
    # #
    #                cols | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 
    #           line text | f |   👧  | o |   | b | a | r |
    #   attrs (style ids) | 0 | 0 | * | 0 | 0 | 1 | 1 | 1 |
    class Line
      attr_accessor :codepoints, :attrs, :widths, :wrapped, :width, :max

      def initialize(max)
        @max = max
        @codepoints = Array.new(max)
        @attrs = Array.new(max)
        @widths = Array.new(max) { 1 }
        @wrapped = false
      end

      # Public: Replaces a char at (col). 
      #         Replace mode adds characters by replacing the character at the cursor position.
      def replace(col, codepoint, attr, charw: codepoint.charwidth(1))
        blank(col, attr)

        # if a wide char, fill in more cols
        (col + 1...col + charw).each do |i|
          blank(i, attr)
          
          codepoints[i] = :continue
          attrs[i] = attr
          widths[i] = 0
        end

        # Put the codepoint in
        codepoints[col] = codepoint
        attrs[col] = attr
        widths[col] = charw
      end

      def delete(col)
        entry = col(col)

        if entry && entry[:width] > 1
          (entry[:index]...(entry[:index] + entry[:width])).each do |i|
            blank(i, 0)
          end
        end

        codepoints.delete_at(col)
        attrs.delete_at(col)
        widths.delete_at(col)
      end

      # Public: Insert mode displays the new character and moves previously displayed characters to the right. 
      #
      def insert(col, codepoint, attr, charw: codepoint.charwidth(1))
        # handle an insert in the middle of a wide char
        if entry = col(col)
          blank(col, attr) if entry[:offset] > 0
        end

        codepoints.insert(col, codepoint)
        attrs.insert(col, attr)
        widths.insert(col, charw)

        if charw > 1
          (col + 1...col + charw).each do |i|
            # blank(i, attr)
            codepoints.insert(i, :continue)
            attrs.insert(i, attr)
            widths.insert(i, 0)
          end
        end

        # truncate any chars at the end.
        codepoints[max..] = []
        attrs[max..] = []
        widths[max..] = []

        if entry = col(max - 1)
          if entry[:width] > 1 && entry[:offset].zero?
            codepoints[max - 1] = SEQR["sp"]
            attrs[max - 1] = attr
            widths[max - 1] = 1
          end
        end
      end

      def blank(col, attr, blank_nil: false)
        if old = col(col)
          ocol = old[:index]
          owidth = old[:width]
          (ocol...ocol + owidth).each do |i|
            codepoints[i] = SEQR["sp"]
            attrs[i] = attr
            widths[i] = 1
          end
        elsif blank_nil
          codepoints[col] = SEQR["sp"]
          attrs[col] = attr
          widths[col] = 1
        end
      end

      # Public: resolves the logical values at col
      #         with consideration to widechars
      # 
      # col - the display column
      # 
      def col(col)
        offset = 0
        i = col
        cp = codepoints[i]
        while cp == :continue
          offset += 1
          cp = codepoints[i -= 1]
        end

        return nil if cp.nil?
          
        {
          index: i,
          char: cp.chr("UTF-8"),
          style_id: attrs[i],
          width: widths[i],
          offset: offset
        }
      end

      def codepoints!
        @codepoints.reject do |cp|
          cp == :continue || cp.nil?
        end
      end

      def to_s
        codepoints!.pack("U*")
      end
    end

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
                    :current_line_width, :cursor, :scrollback, :skip_evict

      attr_reader :session, :rows, :cols, :cursor, :styles, :stylemap, :lines, :current_style

      def initialize(session, rows, cols)
        @session = session
        @rows = rows
        @cols = cols
        @skip_evict = false

        @cursor = Cursor.new(0, 0)
        @scrollback = []
        @tabstops = {}
        @margin_top = 0
        @margin_bottom = rows - 1

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

      def reset_style
        @current_style.reset
        @current_style_id = intern(@current_style)
      end

      def setup_tabstops
        (0...cols).each do |i|
          if i % 8 == 0
            @tabstops[i] = true
          end
        end
      end

      def current_line
        lines[cursor.row]
      end

      def rowcount
        lines.size
      end

      def sgr(ps)
        @current_style.sgr(ps)
        @current_style_id = intern(@current_style)
      end

      def intern(style)
        id = stylemap[style]
        return id if id
  
        snap = style.snapshot.freeze
        styles << snap
        stylemap[snap] = styles.size - 1
      end

      # Internal: Evicts a line of runs into scrollback 
      def evict(line)
        return if skip_evict

        default_id = intern(Style.new)
        current_id = line.attrs[0] || default_id
        runs = []
        chars = ""
        last = line.attrs.rindex { |i| !i.nil? }

        if last.nil?
          scrollback << { chars: "\n", style: styles[default_id] }
          return
        end
  
        (0..last).each do |idx|
          style_id = line.attrs[idx] || default_id
          codepoint = line.codepoints[idx]

          next if codepoint == :continue
          char = codepoint.nil? ? SEQR["sp"] : codepoint

          if current_id != style_id
            runs << { chars: chars, style: styles[current_id] }
            chars = ""
            chars << char
            current_id = style_id
          else
            chars << char
          end
        end

        runs << { chars: chars, style: styles[current_id] }
        if runs[-1] && !runs[-1][:chars].empty?
          runs[-1][:chars] << "\n"
        end

        scrollback.concat runs
      end
      
      def set_cursor(row, col)
        cursor.row = [row, rows - 1].min
        cursor.col = [col, cols - 1].min 
      end

      # Public: index moves the cursor down one line in the same column.
      #         If the cursor is at the bottom margin, the screen performs a scroll-up.
      #         https://vt100.net/docs/vt220-rm/chapter4.html
      def index
        if cursor.row == margin_bottom
          scroll_up
        else
          cursor.row += 1 unless cursor.row >= rows - 1
        end
      end

      def scroll_up(times = 1)
        times.times do
          line = lines.delete_at(margin_top)
          evict(line) if margin_top.zero?
          lines.insert(margin_bottom, Line.new(cols))
        end
      end

      def reverse_index
        if cursor.row == margin_top
          scroll_down
        else
          cursor.row -= 1 unless cursor.row - 1 < 0
        end
      end

      def scroll_down(times = 1)
        times.times do
          lines.delete_at(margin_bottom)
          lines.insert(margin_top, Line.new(cols))
        end
      end

      def next_line
        index

        cursor.col = 0
      end

      # TODO: save / restore cursor
      # tabs
      def tabgoto
        stops = @tabstops.keys.sort
      
        stopped = nil

        stopped = stops.find do |stop|
          stop > cursor.col
        end

        cursor.col = stopped || cols - 1
      end

      def tabset
        @tabstops[cursor.col] = true
      end

      def tabclear(all = false)
        if all
          @tabstops.clear
          return
        end

        @tabstops.delete(cursor.col)
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
        count = (margin_bottom + 1) - cursor.row > count ? count : (margin_bottom + 1) - cursor.row

        # insert the lines
        count.times do
          lines.insert(cursor.row, Line.new(cols))
        end

        # truncate extra rows
        count.times do
          lines.delete_at(margin_bottom + 1)
        end

        # reset the cursor
        cursor.col = 0
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
        count = (margin_bottom + 1) - cursor.row > count ? count : (margin_bottom + 1) - cursor.row

        lines[cursor.row, count] = []

        count.times do
          lines.insert(margin_bottom + 1 - count, Line.new(cols))
        end

        cursor.col = 0
      end

      def insert_chars(count)
        count = 1 if count.zero?

        count.times do
          current_line.insert(cursor.col, SEQR["sp"], intern(Style.new))
        end
      end

      def delete_chars(count)
        count = [count, cols - cursor.col].min

        count.times do
          current_line.delete(cursor.col)

          current_line.codepoints << SEQR["sp"]
          current_line.widths << 1
          current_line.attrs << intern(Style.new)
        end
      end

      # 4.1.2 Erasing
      # Public: Erases characters at the cursor position and the next (count)-1 characters. 
      #         A parameter of 0 or 1 erases a single character. 
      #         Character attributes are set to normal. No reformatting of data on the line occurs. 
      #         The cursor remains in the same position.
      def erase_char(count)
        count = count.zero? ? 1 : count

        count.times do |a|
          i = [cursor.col + a, cols - 1].min

          current_line.blank(i, intern(Style.new), blank_nil: true)
        end
      end

      # Public: Erases parts of the line depending on (mode).
      #         Mode = 0 Erases from the cursor to the end of the line, including the cursor position.
      #                  Line attribute is not affected.
      #         Mode = 1 Erases from the beginning of the line to the cursor, 
      #                 including the cursor position. Line attribute is not affected.
      #         Mode = 2 Erases the complete line.
      # Returns nothing
      def erase_in_line(mode, line: current_line, selective: false)
        return if selective # Not handling (Selective Erase In Line (DECSEL))

        col = [cursor.col, cols - 1].min
        ranges = { 0 => (col...cols), 1 => (0..col), 2 => (0...cols) }
      
        # ignore bad modes
        if range = ranges[mode]
          range.each do |i|
            line.blank(i, intern(Style.new), blank_nil: true)
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
      def erase_in_display(mode, selective: false)
        return if selective # Not Handling (Selective Erase In Display (DECSED))

        ranges = { 0 => (cursor.row + 1...rows), 1 => (0...cursor.row), 2 => (0...rows) }

        # erase the line
        if range = ranges[mode]
          range.each do |row|
            line = lines[row]
            erase_in_line(2, line: line)
          end
        end

        erase_in_line(mode)
      end

      # 4.13 Scrolling margins
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
        cursor.row = 0
        cursor.col = 0
      end

      # Public: Moves the cursor up (count) lines in the same column. 
      #         The cursor stops at the top margin.
      #
      # count - the rows to move up
      def cursor_up(count)
        new_row = cursor.row - count 
        cursor.row = new_row.negative? ? 0 : new_row
      end

      # Public: Moves the cursor down (count) lines in the same column. 
      #         The cursor stops at the bottom margin.
      #
      # count - the rows to move down
      def cursor_down(count)
        new_row = cursor.row + count 
        cursor.row = [new_row, rows - 1].min
      end
      # Public: Moves the cursor right (count) columns. 
      #         The cursor stops at the right margin.
      #
      # count - the columns to move forward
      def cursor_forward(count)
        new_col = cursor.col + count
        offset = session.modes[:decawm] ? 0 : 1
        col_with_offset = new_col > cols - offset ? cols - offset : new_col
        cursor.col = [cols - 1, col_with_offset].min
      end

      # Public: Like cursor_forward but can move into the 
      #         right margin (pending wrap) position
      def advance(count)
        new_col = cursor.col + count
        offset = session.modes[:decawm] ? 0 : 1
        col_with_offset = new_col > cols - offset ? cols - offset : new_col
        cursor.col = col_with_offset
      end

      # Public: Moves the cursor left (count) columns. 
      #         The cursor stops at the left margin.
      #
      # count - the columns to move backward
      def cursor_backward(count)
        new_col = [cursor.col, cols - 1].min - count
        cursor.col = new_col.negative? ? 0 : new_col
      end

      # TODO: UTF-8 Needs to handle grapheme breaks.
      #       The parser can emit ZWJ or other (control) chars.
      #       ref: deps/mruby-utf8proc/src/utf8proc.h#644
      def print(codepoint)
        width = session.width(codepoint)

        # wrap pending and autowrap is on, move the cursor down
        if session.modes[:decawm] && cursor.col + width > cols
          lines[cursor.row].wrapped = true
          cursor.col = 0
          index
        end
  
        line = lines[cursor.row]

        if session.modes[:irm]
          line.insert(cursor.col, codepoint, current_style_id, charw: width)
        else
          col = [cursor.col, cols - width].min
          line.replace(col, codepoint, current_style_id, charw: width)
        end

        advance(width)
      end
    end
  end
end
