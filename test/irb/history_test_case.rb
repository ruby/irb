# frozen_string_literal: false
require "irb"
require "fileutils"
require "tmpdir"

require_relative "helper"

module TestIRB
  class HistoryTestCase < TestCase
    def setup
      @conf_backup = IRB.conf.dup
      @original_verbose, $VERBOSE = $VERBOSE, nil
      @tmpdir = Dir.mktmpdir("test_irb_history_")
      setup_envs(home: @tmpdir)
      IRB.conf[:LC_MESSAGES] = IRB::Locale.new
      save_encodings
      IRB.instance_variable_set(:@existing_rc_name_generators, nil)
    end

    def teardown
      IRB.conf.replace(@conf_backup)
      IRB.instance_variable_set(:@existing_rc_name_generators, nil)
      teardown_envs
      restore_encodings
      $VERBOSE = @original_verbose
      FileUtils.rm_rf(@tmpdir)
    end
  end
end
