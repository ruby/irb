# frozen_string_literal: false
require "irb"
require "irb/extend-command"

require_relative "helper"

class TestIRB::DebugCommandTest < TestIRB::ConsoleTestCase
  def test_debug
    program = <<~'RUBY'
      1| puts "start IRB"
      2| binding.irb
      3| puts "Hello"
    RUBY
    debug_code(program) do
      type 'debug'
      type 'next'
      type 'exit'
    end
    #assert_include_screen(<<~EOC)
    #  (rdbg) next    # command
    #  [1, 3] in #{@ruby_file}
    #       1| puts "start IRB"
    #       2| binding.irb
    #  =>   3| puts "Hello"
    #EOC
  end
end
