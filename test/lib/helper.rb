require "test/unit"
require_relative "core_assertions"

Test::Unit::TestCase.include Test::Unit::CoreAssertions

module Test
  module Unit
    class TestCase
      def windows? platform = RUBY_PLATFORM
        /mswin|mingw/ =~ platform
      end

      def without_rdoc(&block)
        ::Kernel.send(:alias_method, :old_require, :require)

        ::Kernel.define_method(:require) do |name|
          raise LoadError, "cannot load such file -- rdoc (test)" if name.match?("rdoc") || name.match?(/^rdoc\/.*/)
          ::Kernel.send(:old_require, name)
        end

        yield
      ensure
        ::Kernel.send(:alias_method, :require, :old_require)
      end
    end
  end
end
