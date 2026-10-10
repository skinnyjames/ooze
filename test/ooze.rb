module Matchers
  class ErrorBlock < MatchBase
    def initialize(ctx, block)
      @ctx = ctx
      @expected = block
      @error = "Nothing raised"
    end
    
    def match(actual)
      begin
        actual.call

        @error = "Nothing was raised"
        return false
      rescue Exception => ex
        obj = @ctx.instance_exec(ex, &@expected) unless @expected.nil?
        return true if obj.nil?
      end
    end

    def error(actual)
      @error
    end
  end
end

class TestRender
  attr_reader :session

  def initialize(session)
    @session = session
  end

  def render
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
end

module Oozey
  module Harness
    include Theorem::Control::Harness

    load_tests do |options|
      # load app code
      # load test code
      Dir.glob("test/**/*.rb") do |file|
        next if file.include?("ooze.rb")

        eval File.read(file)
      end

      filtered_registry({})
    end
  end
    
  module Hypothesis
    include Harness
    include Theorem::Control::Hypothesis
    include Theorem::StdoutReporter
  end

  class Test
    include Hypothesis
    include Matchers
  end
end

def get_block_by_type(block, type)
  return block if (block.node.ast.type == type) || (block.node.portal&.ast&.has_if_condition? && block.node.portal&.ast&.type == type)

  block.children.each do |child|
    if b = get_block_by_type(child, type)
      return b
    end
  end

  nil
end

def get_blocks_by_type(block, type, results = [])
  if block.node.ast.type == type
    results << block

    return
  end

  block.children.each do |child|
    get_blocks_by_type(child, type, results)
  end

  results
end

eval ruby_file("ooze/terminal.rb")

# Renders a session in ASCII on the screen
def render(session)
  TestRender.new(session).render
end

Oozey::Hypothesis.run!
