require "test/unit"
require "core_assertions"

Test::Unit::TestCase.include Test::Unit::CoreAssertions

module Test
  module Unit
    class TestCase
      def windows? platform = RUBY_PLATFORM
        /mswin|mingw/ =~ platform
      end
    end
  end
end
