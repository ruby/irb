# frozen_string_literal: true
require 'irb'

require_relative "../helper"

module TestIRB
  class ExitProgramTest < IntegrationTestCase
    def test_irb_exit_program
      assert_exits_program(with_status: 0) do
        type "irb_exit_program"
      end
    end

    def test_exit_program
      assert_exits_program(with_status: 0) do
        type "exit_program"
      end
    end

    def test_quit_program
      assert_exits_program(with_status: 0) do
        type "quit_program"
      end
    end

    def test_triple_bang
      assert_exits_program(with_status: 0) do
        type "!!!"
      end
    end

    def test_exit_code_zero
      assert_exits_program(with_status: 0) do
        type "!!! 0"
      end
    end

    def test_exit_code_one
      assert_exits_program(with_status: 1) do
        type "!!! 1"
      end
    end

    def test_exit_code_expression
      assert_exits_program(with_status: 2) do
        type "n = 1"
        type "!!! n + 1"
      end
    end

    private

    def assert_exits_program(with_status:, &block)
      write_ruby <<~'RUBY'
        begin
          binding.irb
          puts "Did not raise #{SystemExit}!" # Interpolate so we don't match whereami context
        rescue SystemExit => e
          puts "Raised SystemExit with status #{e.status.inspect}"
        end
      RUBY

      output = run_ruby_file(&block)

      refute_includes(output, "Did not raise SystemExit!", "AN ERROR MESSAGE")
      matching_status = output[/(?<=Raised SystemExit with status )(\d+)/]
      refute_nil matching_status, "Did not find exit status in output: \n#{output}"
      assert_equal with_status, matching_status.to_i, "Exited with wrong status code"
    end
  end
end
