
module SessionHelpers
  UNICODE_REPLACE = "\uFFFD"

  def render(session)
    rows = []

    header = []
    dheader = []
    (0...session.screen.cols).each do |col|
      header << col.to_s.center(3)
      dheader << "---"
    end

    rows << "|#{header.join("|")}|"
    rows << "|#{dheader.join("|")}|"

    (0...session.screen.rows).each do |row|
      line = session.screen.lines[row]
      cp = nil
      wc = nil
      st = nil

      row = []
      srow = []
      drow = []

      (0...session.screen.cols).each do |col|
        drow << "---"

        if entry = line.col(col)
          if entry[:offset] > 0
            srow << " * "
            next
          end
  
          cp = entry[:char]
          wc = entry[:width]
          st = entry[:style_id]

          if entry && wc == 1
            row << " #{cp} "
            srow << " #{st} "
            next
          elsif entry && wc > 1
            start = (wc * 3) / 2.0 
            row << [" " * start, cp, " " * ((wc * 3) - start - 1)].join("")
            srow << " #{st} "
            next
          end
        end

        row << "   "
        srow << "   "
      end

      rows << "|#{row.join("|")}|"
      rows << "|#{srow.join("|")}|"
      rows << "|#{drow.join("|")}|"
    end

    "\n#{rows.join("\n")}\n"
  end

  def row(line)
    trans = line.codepoints.map do |cp|
      case cp
      when nil
        "_"
      when :continue
        "*"
      else
        cp.chr("UTF-8")
      end
    end

    trans.join("").gsub(/_+$/, "")
  end

  def styles(line)
    line.attrs.reject(&:nil?).join("")
  end

  def insert(line, col, char)
    line.insert(col, char.ord, 0)
    row(line)
  end

  def replace(line, cursor, char)
    line.replace(cursor, char.ord, 0)
    row(line)
  end

  def line(chars, max = 8)
    line = Ooze::Terminal::Line.new(max)
    counter = 0

    chars.split("").each do |char|
      replace(line, counter, char)
      counter += char.width
    end

    line
  end

  def parse(str, rows: 8, cols: 8, using: nil, secret: nil)
    seq = Ooze::Terminal::SEQ[str].pack("U*").freeze
    pty = Struct.new(:size).new([rows, cols])
    session = using || Ooze::Terminal::Session.new(pty, secret: secret)
    session.parser.parse(seq)
    session
  end

  def dec_code(key)
    0x80 | Ooze::Terminal::DEC_MN_CODE_TABLE[key]
  end

  def code(key)
    Ooze::Terminal::ASCII_CODE_TABLE[key]
  end

end
