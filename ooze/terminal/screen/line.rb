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
      attr_accessor :dirty

      def initialize(max)
        @max = max
        @codepoints = Array.new(max)
        @attrs = Array.new(max)
        @widths = Array.new(max) { 1 }
        @wrapped = false
        
        # vars for caching
        @dirty = true
        @runs = nil # cached runs
      end

      # Public: Retunrs an array of runs for the line
      #         If the line is not flagged as dirty, cached runs will be returned.
      #         Otherwise they will be built
      #
      # default_style_id - A fallback style id to use for nil columns
      # 
      # Returns Array(Array(chars, style_id))
      def runs(default_id)
        return @runs unless @dirty

        sid = @attrs[0] || default_id
        cache = []
        run = []
        last = @codepoints.rindex { |i| !i.nil? }

        if last.nil?
          @runs = []
          @dirty = false
          return @runs
        end
        
        (0..last).each do |idx|
          attr = @attrs[idx] || default_id
          cp = @codepoints[idx]
      
          # run
          if sid != attr
            cache << [run.pack("U*"), sid]

            run.clear
            sid = attr
          end

          if cp.nil?
            run << SEQR["sp"]
          elsif cp != :continue
            run << cp
          end
        end

        cache << [run.pack("U*"), sid]

        @runs = cache
        @dirty = false
        return @runs
      end

      # Public: Replaces a char at (col).
      #         Replace mode adds characters by replacing the character at the cursor position.
      #
      # col - the screen colum of the line to replace (Integer)
      # codepoint - the codepoint to replace at (col) (Integer)
      # attr - the style id of this codepoint (Integer)
      # width - the width of (codepoint) (Integer)
      #
      # Examples
      #   
      #   line # => <Line @codepoints=["a", "b", "c", "d"]>
      #   line.replace(1, "e", 1, 1) # => <Line @codepoints=["a", "e", "c", "d"]>
      #   line.replace(2, "👧", 1, 2) # => <Line @codepoints=["a", "e", "👧", :continue]>
      #
      # Returns nothing
      def replace(col, codepoint, attr, charw = codepoint.charwidth(1))
        @dirty = true

        if charw == 1 && @widths[col] == 1 && @codepoints[col] != :continue
          @codepoints[col] = codepoint
          @attrs[col] = attr
  
          return
        end

        blank(col, attr)

        # if a wide char, fill in more cols
        (col + 1...col + charw).each do |i|
          blank(i, attr)
          
          @codepoints[i] = :continue
          @attrs[i] = attr
          @widths[i] = 0
        end

        # Put the codepoint in
        @codepoints[col] = codepoint
        @attrs[col] = attr
        @widths[col] = charw
      end

      # Public: Delete the values at (col)
      #         If col is the head or tail of a widechar,
      #         the rest of the widechars columns will be blanked.
      #         
      # col - the column to delete
      # 
      # Returns nothing
      def delete(col)
        @dirty = true

        entry = col(col)

        if entry && entry[:width] > 1
          (entry[:index]...(entry[:index] + entry[:width])).each do |i|
            blank(i, 0)
          end
        end

        @codepoints.delete_at(col)
        @attrs.delete_at(col)
        @widths.delete_at(col)
      end

      # Public: Insert a new character and 
      #         move previously displayed characters to the right. 
      #         Moved characters past @max - 1 will be truncated
      # 
      # col - the column to insert at (Integer)
      # codepoint - the codepoint to insert (Integer)
      # attr - the style id of this codepoint (Integer)
      # charw - the width of this codepoint (Integer)
      # 
      # Examples
      # 
      #   line # => <Line @max=4 @codepoints=["a", "b", "c", "d"]>
      #   line.insert(1, "e", 1, 1) # => <Line @codepoints=["a", "e", "b", "c"]>
      #   line.insert(0, "👧", 1, 2) # => <Line @codepoints=["👧", :continue, "a", "e"]>
      #
      def insert(col, codepoint, attr, charw = codepoint.charwidth(1))
        @dirty = true

        # handle an insert in the middle of a wide char
        if entry = col(col)
          blank(col, attr) if entry[:offset] > 0
        end

        @codepoints.insert(col, codepoint)
        @attrs.insert(col, attr)
        @widths.insert(col, charw)

        if charw > 1
          (col + 1...col + charw).each do |i|
            # blank(i, attr)
            @codepoints.insert(i, :continue)
            @attrs.insert(i, attr)
            @widths.insert(i, 0)
          end
        end

        # truncate any chars at the end.
        @codepoints[max..] = []
        @attrs[max..] = []
        @widths[max..] = []

        if entry = col(max - 1)
          if entry[:width] > 1 && entry[:offset].zero?
            @codepoints[max - 1] = SEQR["sp"]
            @attrs[max - 1] = attr
            @widths[max - 1] = 1
          end
        end
      end

      # Public: Sets the value at (col) to a space. 
      #         If (col) is the head or tail of a widechar, each column will be blanked.
      # 
      # col - the column to blank
      # attr - the style id to use for the space
      # kwargs
      #   :blank_nil - if true, turn a nil column into a space
      # 
      # Returns nothing
      def blank(col, attr, blank_nil: false)
        @dirty = true

        if old = col(col)
          ocol = old[:index]
          owidth = old[:width]
          (ocol...ocol + owidth).each do |i|
            @codepoints[i] = SEQR["sp"]
            @attrs[i] = attr
            @widths[i] = 1
          end
        elsif blank_nil
          @codepoints[col] = SEQR["sp"]
          @attrs[col] = attr
          @widths[col] = 1
        end
      end

      # Public: Removes all codepoints, styles, and widths
      #         and resets line to initial state
      #         
      # Returns nothing
      def clear
        @codepoints.clear
        @codepoints[@max - 1] = nil

        @attrs.clear
        @attrs[@max - 1] = nil

        @widths.fill(1)
        @wrapped = false
        @dirty = true
      end

      # Public: resolves the UTF-8 char at col
      # 
      # col - the display column
      # 
      # Returns nil or String
      def char_at(col)
        index = col(col)&.dig(:index)
        return nil if index.nil?

        @codepoints[index].chr("UTF-8")
      end

      # Public: resolves the logical values at col
      #         with consideration to widechars
      # 
      # col - the display column
      # 
      # Examples
      #
      #   line # =>  <Line @codepoints=["👧", :continue, "a", "e"]>
      #   line.col(2) # => { index: 2, style_id: 1, width: 1, offset: 0 }
      #   line.col(1) # => { index: 0, style_id: 1, width: 2, offset: 1 }
      # 
      # Returns Hash(
      #   index: origin index of col (Integer)
      #   style_id: the style id for col (Integer)
      #   width: the width of the codepoint at col (Integer) 
      #   offset: the offset of the char at col.  widechar tails will be offset > 0 (Integer)
      # )
      def col(col)
        offset = 0
        i = col
        cp = @codepoints[i]
        while cp == :continue
          offset += 1
          cp = @codepoints[i -= 1]
        end

        return nil if cp.nil?
          
        {
          index: i,
          style_id: @attrs[i],
          width: @widths[i],
          offset: offset
        }
      end

      # Internal: Returns the lines codepoints
      #           (For testing)
      def codepoints!
        @codepoints.reject do |cp|
          cp == :continue || cp.nil?
        end
      end

      # Internal: Returns a String representation of this line
      #           (For testing)
      def to_s
        codepoints!.pack("U*")
      end
    end
  end
end