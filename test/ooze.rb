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

module Ooze
  module Harness
    include Theorem::Control::Harness

    load_tests do |options|
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

Ooze::Hypothesis.run!
