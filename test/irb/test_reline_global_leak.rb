# frozen_string_literal: true
require "irb"
require_relative "helper"

module TestIRB
  class RelineGlobalLeakTest < IntegrationTestCase
    def test_reline_autocompletion_is_restored_after_irb_exit
      write_ruby <<~'RUBY'
        require 'reline'

        Reline.autocompletion = false
        puts "Before: #{Reline.autocompletion}"

        binding.irb

        puts "After: #{Reline.autocompletion}"
      RUBY

      output = run_ruby_file do
        type "exit"
      end

      assert_include output, "Before: false"
      assert_include output, "After: false"
    end
  end
end
