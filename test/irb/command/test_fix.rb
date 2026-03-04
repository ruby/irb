# frozen_string_literal: true

require "irb"
require_relative "../helper"

module TestIRB
  class FixCommandTest < TestCase
    def setup
      IRB::Command::LastError.clear
    end

    def teardown
      IRB::Command::LastError.clear
    end

    def test_fix_command_shows_hint_on_did_you_mean_error
      pend "did_you_mean is disabled" unless did_you_mean_available?

      out, err = execute_lines("1.zeor?", "fix")

      assert_match(/Did you mean\?\s+zero\?/, out)
      assert_match(/Type `fix` to rerun with the correction\./, out)
      assert_match(/Rerunning with: 1\.zero\?/, out)
      assert_match(/=> (true|false)/, out)
      assert_empty(err)
    end

    def test_fix_command_reruns_with_correction
      pend "did_you_mean is disabled" unless did_you_mean_available?

      out, err = execute_lines("1.zeor?", "fix")

      assert_match(/Rerunning with: 1\.zero\?/, out)
      assert_empty(err)
    end

    def test_fix_command_without_previous_error
      out, err = execute_lines("fix")

      assert_match(/No previous error with Did you mean\? suggestions/, out)
      assert_empty(err)
    end

    def test_fix_command_clears_after_success
      pend "did_you_mean is disabled" unless did_you_mean_available?

      execute_lines("1.zeor?", "fix")
      out, err = execute_lines("fix")

      assert_match(/No previous error with Did you mean\? suggestions/, out)
      assert_empty(err)
    end

    def test_retry_alias_works
      pend "did_you_mean is disabled" unless did_you_mean_available?

      out, err = execute_lines("1.zeor?", "retry")

      assert_match(/Rerunning with: 1\.zero\?/, out)
      assert_empty(err)
    end

    def test_last_error_stored_on_correctable_exception
      pend "did_you_mean is disabled" unless did_you_mean_available?

      execute_lines("1.zeor?")

      assert_not_nil(IRB::Command::LastError.last_code)
      assert_not_nil(IRB::Command::LastError.last_exception)
      assert_equal("1.zeor?", IRB::Command::LastError.last_code)
    end

    def test_last_error_cleared_on_uncorrectable_exception
      execute_lines("raise 'oops'")

      assert_nil(IRB::Command::LastError.last_code)
      assert_nil(IRB::Command::LastError.last_exception)
    end

    private

    def did_you_mean_available?
      return false unless defined?(DidYouMean)
      1.zeor?
    rescue NoMethodError => e
      e.respond_to?(:corrections) && !e.corrections.to_a.empty?
    end
  end
end
