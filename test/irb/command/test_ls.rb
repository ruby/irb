require "tempfile"
require_relative "../helper"

module TestIRB
  class LSTest < IntegrationTestCase
    def setup
      super

      write_ruby <<~'RUBY'
        class Foo
          class Bar
            def bar
              "this is bar"
            end
          end

          def foo
            "this is foo"
          end
        end

        class BO < BasicObject
          ONE = 1
          def baz
            "this is baz"
          end
        end

        binding.irb
      RUBY
    end

    def test_ls_class
      out = run_ruby_file do
        type "ls Foo"
        type "exit"
      end

      assert_match(/constants: Bar/, out)
      assert_match(/Foo#methods: foo/, out)
    end

    def test_ls_instance
      out = run_ruby_file do
        type "ls Foo.new"
        type "exit"
      end

      assert_match(/Foo#methods: foo/, out)
    end

    def test_ls_basic_object
      out = run_ruby_file do
        type "ls BO"
        type "exit"
      end

      assert_match(/constants:.*ONE/, out)
      assert_match(/BO#methods: baz/, out)
    end

    def test_ls_basic_object_instance
      out = run_ruby_file do
        type "ls BO.new"
        type "exit"
      end

      assert_match(/BO#methods: baz/, out)
    end
  end
end
