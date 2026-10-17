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

  class LessThan < ::Matchers::MatchBase
    def match(actual)
      @expected >= actual
    end

    def error(actual)
      "#{actual.inspect} is not less than #{@expected.inspect}"
    end
  end

  def be_less_than(expected)
    LessThan.new(expected)
  end
end

require_relative "./helpers/session_helpers"

module Oozey
  module Harness
    include Theorem::Control::Harness

    load_tests do |options|
      # load app code
      # load test code
      Dir.glob("test/**/*.rb") do |file|
        next if file.include?("ooze.rb") || file.include?("esctest.rb")

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
    include ::SessionHelpers
  end
end

eval ruby_file("ooze/terminal.rb")

Oozey::Hypothesis.run!
