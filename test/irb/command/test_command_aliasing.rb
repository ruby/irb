# frozen_string_literal: true

require "tempfile"
require_relative "../helper"

module TestIRB
  class CommandAliasingTest < IntegrationTestCase
    def setup
      super
      write_rc <<~RUBY
        IRB.conf[:COMMAND_ALIASES] = {
          :c => :conf, # alias to helper method
          :f => :foo
        }
      RUBY

      write_ruby <<~'RUBY'
        binding.irb
      RUBY
    end

    def test_aliasing_to_helper_method_triggers_warning
      out = run_ruby_file do
        type "c"
        type "exit"
      end
      assert_include(out, "Using command alias for helper method 'conf' is not supported")
      assert_not_include(out, "Maybe IRB bug!")
    end

    def test_incorrect_alias_triggers_warning
      out = run_ruby_file do
        type "f"
        type "exit"
      end
      assert_include(out, "Command 'foo' does not exist")
      assert_not_include(out, "Maybe IRB bug!")
    end
  end
end
