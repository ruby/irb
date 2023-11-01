# frozen_string_literal: false
require 'irb/source_finder'

require_relative "helper"

module TestIRB
  class SourceFinderTest < TestCase
    def setup
      @source_finder = IRB::SourceFinder.new(TOPLEVEL_BINDING)
    end

    def test_find_source
      first_line = __LINE__ - 1
      source = @source_finder.find_source('TestIRB::SourceFinderTest#test_find_source')
      assert_equal(__FILE__, source.file)
      assert_equal(first_line, source.first_line)
      assert_equal(__LINE__ + 1, source.last_line)
    end

    def test_find_end
      assert_equal(4, @source_finder.send(:find_end, <<~RUBY, 2))
        class A
          def foo
            42
          end
        end
      RUBY

      assert_equal(2, @source_finder.send(:find_end, <<~RUBY, 2))
        class A
          def foo() = 42
        end
      RUBY

      assert_equal(4, @source_finder.send(:find_end, <<~RUBY, 2))
        class A
          B = Struct.new(
            :foo
          )
        end
      RUBY

      assert_equal(5, @source_finder.send(:find_end, <<~'RUBY', 3))
        class A
          eval(<<~CODE, binding, __FILE__, __LINE__ + 1)
            def #{method_name}
              42
            end
          CODE
        end
      RUBY

      assert_equal(5, @source_finder.send(:find_end, <<~'RUBY', 2))
        class A
          def f(a = <<~CODE)
            CODE
            42
          end
        end
      RUBY

      assert_equal(4, @source_finder.send(:find_end, <<~'RUBY', 2))
        class A
          define_method(:bar) do
            42
          end.then do
            42
          end
        end
      RUBY
    end
  end
end
