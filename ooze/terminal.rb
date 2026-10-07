module Ooze
  module Terminal
    # Based on the VT220 Programmers reference manual
    # https://www.vt100.net/docs/vt220-rm/

    # ASCII Code table (occupies the C0 range starting on the 1st bit to 7th)
    ASCII_CODE_TABLE = {
      nul: 0x00, soh: 0x01, stx: 0x02, etx: 0x03, eot: 0x04, enq: 0x05,
      ack: 0x06, bel: 0x07, bs: 0x08, ht: 0x09, lf: 0x0A, vt: 0x0B, 
      ff: 0x0C, cr: 0x0D, so: 0x0E, si: 0x0F, dle: 0x10, dc1: 0x11,
      dc2: 0x12, dc3: 0x13, dc4: 0x14, nak: 0x15, syn: 0x16, etb: 0x17,
      can: 0x18, em: 0x19, sub: 0x1A, esc: 0x1B, fs: 0x1C, gs: 0x1D,
      rs: 0x1E, us: 0x1F, sp: 0x20, del: 0x7F,
      '!' => 0x21, '"' => 0x22, "#" => 0x23, '$' => 0x24, '%' => 0x25,
      '&' => 0x26, "'" => 0x27, '(' => 0x28, ')' => 0x29, '*' => 0x2A,
      '+' => 0x2B, ',' => 0x2C, '-' => 0x2D, '.' => 0x2E, '/' => 0x2F,
      '0' => 0x30, '1' => 0x31, '2' => 0x32, '3' => 0x33, '4' => 0x34,
      '5' => 0x35, '6' => 0x36, '7' => 0x37, '8' => 0x38, '9' => 0x39,
      ':' => 0x3A, ';' => 0x3B, '<' => 0x3C, '=' => 0x3D, '>' => 0x3E,
      '?' => 0x3F, '@' => 0x40, 'A' => 0x41, 'B' => 0x42, 'C' => 0x43,
      'D' => 0x44, 'E' => 0x45, 'F' => 0x46, 'G' => 0x47, 'H' => 0x48,
      'I' => 0x49, 'J' => 0x4A, 'K' => 0x4B, 'L' => 0x4C, 'M' => 0x4D,
      'N' => 0x4E, 'O' => 0x4F, 'P' => 0x50, 'Q' => 0x51, 'R' => 0x52,
      'S' => 0x53, 'T' => 0x54, 'U' => 0x55, 'V' => 0x56, 'W' => 0x57,
      'X' => 0x58, 'Y' => 0x59, 'Z' => 0x5A, '[' => 0x5B, '\\' => 0x5C,
      ']' => 0x5D, '^' => 0x5E, '_' => 0x5F, '`' => 0x60, 'a' => 0x61, 
      'b' => 0x62, 'c' => 0x63, 'd' => 0x64, 'e' => 0x65, 'f' => 0x66, 
      'g' => 0x67, 'h' => 0x68, 'i' => 0x69, 'j' => 0x6A, 'k' => 0x6B, 
      'l' => 0x6C, 'm' => 0x6D, 'n' => 0x6E, 'o' => 0x6F, 'p' => 0x70, 
      'q' => 0x71, 'r' => 0x72, 's' => 0x73, 't' => 0x74, 'u' => 0x75, 
      'v' => 0x76, 'w' => 0x77, 'x' => 0x78, 'y' => 0x79, 'z' => 0x7A, 
      '{' => 0x7B, '|' => 0x7C, '}' => 0x7D, '~' => 0x7E, 
    }.freeze

    ASCII_MAX = 0x80.freeze

    # DEC Multinational charset  (occupies the C1 - GR range offset by the 8th bit)
    # Actual values are (0x80 | value)
    # LEGACY (Pre Unicode - For reference)
    DEC_MN_CODE_TABLE = {
      ind: 0x04, nel: 0x05, ssa: 0x06, esa: 0x07, hts: 0x08, htj: 0x09,
      vts: 0x0A, pld: 0x0B, plu: 0x0C, ri: 0x0D, ss2: 0x0E, ss3: 0x0F,
      dcs: 0x10, pu1: 0x11, pu2: 0x12, sts: 0x13, cch: 0x14,
      mw: 0x15,  spa: 0x16, epa: 0x17, csi: 0x1B, st: 0x1C, osc: 0x1D,
      pm: 0x1E, apc: 0x1F,
      '¡' => 0x21, '¢' => 0x22, '£' => 0x23, '¥' => 0x25, '§' => 0x27,
      '¤' => 0x28, '©' => 0x29, 'ª' => 0x2A, '«' => 0x2B, '°' => 0x30,
      '±' => 0x31, '²' => 0x32, '³' => 0x33, 'µ' => 0x35, '¶' => 0x36, 
      '·' => 0x37, '¹' => 0x39, 'º' => 0x3A, '»' => 0x3B, '¼' => 0x3C,
      '½' => 0x3D, '¿' => 0x3F, 'À' => 0x40, 'Á' => 0x41, 'Â' => 0x42,
      'Ã' => 0x43, 'Ä' => 0x44, 'Å' => 0x45, 'Æ' => 0x46, 'Ç' => 0x47,
      'È' => 0x48, 'É' => 0x49, 'Ê' => 0x4A, 'Ë' => 0x4B, 'Ì' => 0x4C,
      'Í' => 0x4D, 'Î' => 0x4E, 'Ï' => 0x4F, 'Ñ' => 0x51, 'Ò' => 0x52,
      'Ó' => 0x53, 'Ô' => 0x54, 'Õ' => 0x55, 'Ö' => 0x56, 'Œ' => 0x57,
      'Ø' => 0x58, 'Ù' => 0x59, 'Ú' => 0x5A, 'Û' => 0x5B, 'Ü' => 0x5C,
      'Ÿ' => 0x5D, 'ß' => 0x5F, 'à' => 0x60, 'á' => 0x61, 'â' => 0x62, 
      'ã' => 0x63, 'ä' => 0x64, 'å' => 0x65, 'æ' => 0x66, 'ç' => 0x67, 
      'è' => 0x68, 'é' => 0x69, 'ê' => 0x6A, 'ë' => 0x6B, 'ì' => 0x6C, 
      'í' => 0x6D, 'î' => 0x6E, 'ï' => 0x6F, 'ñ' => 0x71, 'ò' => 0x72, 
      'ó' => 0x73, 'ô' => 0x74, 'õ' => 0x75, 'ö' => 0x76, 'œ' => 0x77, 
      'ø' => 0x78, 'ù' => 0x79, 'ú' => 0x7A, 'û' => 0x7B, 'ü' => 0x7C, 
      'ÿ' => 0x7D
    }.freeze

    class SEQ
      def self.[](str)
        tokens = str.split(" ")
        values = []
        while token = tokens.shift
          if token.size > 1
            if (token.start_with?("\"")  || token.start_with?("'"))
              quot = token[0]
              stack = [token]

              while !stack[-1].end_with?(quot)
                newtoken = tokens.shift
                raise "Unterminated #{quot} in SEQ" if newtoken.nil?

                stack << newtoken
              end

              aggregate = stack.join(" ")

              values.concat aggregate[1...-1].split("").map { |c| c.ord }
            elsif token =~ /^[A-Z][A-Z0-9]+$/
              values.concat Terminal.const_get(token)
            elsif token =~ /^[0-9]+$/
              values.concat token.split("").map { |num| ASCII_CODE_TABLE[num] }
            else
              value = ASCII_CODE_TABLE[token.downcase.to_sym]
              raise "SEQ: Can't find #{token.to_sym} in ASCII_CODE_TABLE" if value.nil?
              values << value
            end
          else
            values << ASCII_CODE_TABLE[token]
          end
        end

        values
      end
    end

    class SEQR
      def self.[](str)
        tokens = str.split(" ")
        case tokens.size
        when 1
          raise "No compound args" if SEQ[tokens[0]].size > 1

          return SEQ[tokens[0]][0].freeze
        when 3
          if tokens[1] == ".."
            raise "No compound args" if SEQ[tokens[0]].size > 1 || SEQ[tokens[2]].size > 1

            return (SEQ[tokens[0]][0]..SEQ[tokens[2]][0]).freeze
          end
        end

        raise "Should be a single value or range"
      end
    end

    # Control Sequence Introducer
    # https://en.wikipedia.org/wiki/ANSI_escape_code#Control_Sequence_Introducer_commands
    # Using ASCII represenation instead of C1 set.
    CSI = SEQ["esc ["].freeze
    OSC = SEQ["esc ]"].freeze
    
    # Single Shift G3
    # https://www.vt100.net/docs/vt220-rm/chapter4.html#F4-3
    # Moves the next graphic char from G3 (Graphics 3) into GL (ASCII charset) 
    SS3 = SEQ["esc O"].freeze
  end
end

require_relative './terminal/session'
require_relative './terminal/input'
require_relative './terminal/parser'
require_relative "./terminal/screen"