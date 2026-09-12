# frozen_string_literal: true
require "irb"

require_relative "helper"

module TestIRB
  class HelperMethodTestCase < TestCase
    def setup
      $VERBOSE = nil
      @verbosity = $VERBOSE
      save_encodings
      IRB.instance_variable_get(:@CONF).clear
    end

    def teardown
      $VERBOSE = @verbosity
      restore_encodings
    end
  end

  module TestHelperMethod
    class ConfTest < HelperMethodTestCase
      def test_conf_returns_the_context_object
        out, err = execute_lines("conf.ap_name")

        assert_empty err
        assert_include out, "=> \"irb\""
      end

      def test_conf_variations
        out, err = execute_lines('p "1:#{conf.ap_name}"; p "2:#{self.then { conf().ap_name }}"; p(x:conf.ap_name+"3")')

        assert_empty err
        assert_include out, '"1:irb"'
        assert_include out, '"2:irb"'
        assert_include out, '"irb3"'
      end

      def test_conf_code_injection
        assert_equal '::IRB::HelperMethod::Container.conf.ap_name', IRB::HelperMethod.inject_helper_methods('conf.ap_name', local_variables: [])
        assert_equal 'conf.ap_name', IRB::HelperMethod.inject_helper_methods('conf.ap_name', local_variables: [:conf])
        assert_equal 'a /conf#{::IRB::HelperMethod::Container.conf}/', IRB::HelperMethod.inject_helper_methods('a /conf#{conf}/', local_variables: [])
        assert_equal 'a /::IRB::HelperMethod::Container.conf#{conf}/', IRB::HelperMethod.inject_helper_methods('a /conf#{conf}/', local_variables: [:a])
        assert_equal(
          '::IRB::HelperMethod::Container.conf.ap_name; conf = 1; conf.ap_name; class A; ::IRB::HelperMethod::Container.conf.ap_name; end',
          IRB::HelperMethod.inject_helper_methods('conf.ap_name; conf = 1; conf.ap_name; class A; conf.ap_name; end')
        )
      end

      def test_conf_completion
        assert_include IRB::HelperMethod.completions('loop do |_conf| ', 'co', local_variables: []), 'conf'
        assert_include IRB::HelperMethod.completions('def f(x=', 'co', local_variables: []), 'conf'
        assert_not_include IRB::HelperMethod.completions('def f(', 'co', local_variables: []), 'conf'
        assert_include IRB::HelperMethod.completions("a /1#/i;'\n", 'co', local_variables: [:a]), 'conf'
        assert_not_include IRB::HelperMethod.completions("a /1#/i;'\n", 'co', local_variables: []), 'conf'
      end
    end

    class ColorizationTest < HelperMethodTestCase
      def test_colorize_helper_method
        # Without helper_methods: used in inspect result
        assert_equal(
          "\e[36mconf\e[0m[]; \e[36mconf\e[0m(); +\e[36mconf\e[0m",
          IRB::Color.colorize_code('conf[]; conf(); +conf', colorable: true)
        )

        # With helper_methods: used in syntax highlighting
        assert_equal(
          "\e[1mconf\e[0m[]; \e[1mconf\e[0m(); +\e[1mconf\e[0m",
          IRB::Color.colorize_code('conf[]; conf(); +conf', colorable: true, helper_methods: true)
        )

        # If receiver exists, it's not a helper method
        assert_not_include(IRB::Color.colorize_code('tap{self.conf}', colorable: true, helper_methods: true), "\e[1mconf\e[0m")
        # ImplicitNode is not supported
        assert_not_include(IRB::Color.colorize_code('p(conf:)', colorable: true, helper_methods: true), "\e[1mconf\e[0m")
      end

      def test_colorize_legacy_command_bundle_helper_method
        IRB::ExtendCommandBundle.define_method(:my_helper) {}
        assert_equal(
          "\e[1mmy_helper\e[0m[]; \e[1mmy_helper\e[0m(); +\e[1mmy_helper\e[0m",
          IRB::Color.colorize_code('my_helper[]; my_helper(); +my_helper', colorable: true, helper_methods: true)
        )
      ensure
        IRB::ExtendCommandBundle.remove_method(:my_helper)
      end
    end
  end

  class HelperMethodIntegrationTest < IntegrationTestCase
    def test_arguments_propogation
      write_ruby <<~RUBY
        require "irb/helper_method"

        class MyHelper < IRB::HelperMethod::Base
          description "This is a test helper"

          def execute(
            required_arg, optional_arg = nil, *splat_arg, required_keyword_arg:,
            optional_keyword_arg: nil, **double_splat_arg, &block_arg
          )
            puts [required_arg, optional_arg, splat_arg, required_keyword_arg, optional_keyword_arg, double_splat_arg, block_arg.call].to_s
          end
        end

        IRB::HelperMethod.register(:my_helper, MyHelper)

        binding.irb
      RUBY

      output = run_ruby_file do
        type <<~INPUT
          my_helper(
            "required", "optional", "splat", required_keyword_arg: "required",
            optional_keyword_arg: "optional", a: 1, b: 2
          ) { "block" }
        INPUT
        type "exit"
      end

      optional = {a: 1, b: 2}
      assert_include(output, %[["required", "optional", ["splat"], "required", "optional", #{optional.inspect}, "block"]])
    end

    def test_helper_method_injection_can_happen_after_irb_require
      write_ruby <<~RUBY
        require "irb"

        class MyHelper < IRB::HelperMethod::Base
          description "This is a test helper"

          def execute
            puts "Hello from MyHelper"
          end
        end

        IRB::HelperMethod.register(:my_helper, MyHelper)

        binding.irb
      RUBY

      output = run_ruby_file do
        type "my_helper"
        type "exit"
      end

      assert_include(output, 'Hello from MyHelper')
    end

    def test_helper_method_instances_are_memoized
      write_ruby <<~RUBY
        require "irb/helper_method"

        class MyHelper < IRB::HelperMethod::Base
          description "This is a test helper"

          def execute(val)
            @val ||= val
          end
        end

        IRB::HelperMethod.register(:my_helper, MyHelper)

        binding.irb
      RUBY

      output = run_ruby_file do
        type "my_helper(100)"
        type "my_helper(200)"
        type "exit"
      end

      assert_include(output, '=> 100')
      assert_not_include(output, '=> 200')
    end
  end
end
