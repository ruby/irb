require "tempfile"
require_relative "../helper"

module TestIRB
  class CDTest < IntegrationTestCase
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

        binding.irb
      RUBY
    end

    def test_cd
      out = run_ruby_file do
        type "cd Foo"
        type "ls"
        type "cd Bar"
        type "ls"
        type "cd .."
        type "exit"
      end

      assert_match(/irb\(Foo\):002>/, out)
      assert_match(/Foo#methods: foo/, out)
      assert_match(/irb\(Foo::Bar\):004>/, out)
      assert_match(/Bar#methods: bar/, out)
      assert_match(/irb\(Foo\):006>/, out)
    end

    def test_dash_switches_between_the_last_two_contexts
      out = run_ruby_file do
        type "cd Foo"
        type "cd Bar"
        type "cd -"
        type "cd -"
        type "cd"
        type "cd -"
        type "cd -"
        type "exit"
      end

      assert_match(/irb\(Foo::Bar\):003>/, out)
      assert_match(/irb\(Foo\):004>/, out)
      assert_match(/irb\(Foo::Bar\):005>/, out)
      assert_match(/irb\(main\):006>/, out)
      assert_match(/irb\(Foo::Bar\):007>/, out)
      assert_match(/irb\(main\):008>/, out)

      out = run_ruby_file do
        type "cd -"
        type "cd Foo"
        type "cd -"
        type "cd -"
        type "cd Bar"
        type "cd .."
        type "cd -"
        type "exit"
      end

      assert_match(/irb\(Foo\):003>/, out)
      assert_match(/irb\(main\):004>/, out)
      assert_match(/irb\(Foo\):005>/, out)
      assert_match(/irb\(Foo::Bar\):006>/, out)
      assert_match(/irb\(Foo\):007>/, out)
      assert_match(/irb\(Foo::Bar\):008>/, out)
    end

    def test_cd_moves_top_level_with_no_args
      out = run_ruby_file do
        type "cd Foo"
        type "cd Bar"
        type "cd"
        type "exit"
      end

      assert_match(/irb\(Foo::Bar\):003>/, out)
      assert_match(/irb\(main\):004>/, out)
    end

    def test_cd_with_error
      out = run_ruby_file do
        type "cd Baz"
        type "exit"
      end

      assert_match(/Error: uninitialized constant Baz/, out)
      assert_match(/irb\(main\):002>/, out) # the context should not change
    end
  end
end
