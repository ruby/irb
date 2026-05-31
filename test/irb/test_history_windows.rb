# frozen_string_literal: false
require "irb"
require "fileutils"
require "tmpdir"

require_relative "helper"

module TestIRB
  class HistoryWindowsTest < TestCase
    class TestInputMethodWithHistory < TestInputMethod
      HISTORY = []

      include IRB::HistorySavingAbility

      def gets
        super&.tap do |line|
          HISTORY << line unless line.empty?
        end
      end
    end

    def setup
      @conf_backup = IRB.conf.dup
      @original_verbose, $VERBOSE = $VERBOSE, nil
      IRB.instance_variable_set(:@existing_rc_name_generators, nil)
    end

    def teardown
      IRB.conf.replace(@conf_backup)
      IRB.instance_variable_set(:@existing_rc_name_generators, nil)
      TestInputMethodWithHistory::HISTORY.clear
      $VERBOSE = @original_verbose
    end

    def test_history_is_saved_in_readonly_attributed_directory
      omit "Windows-only" unless windows?

      Dir.mktmpdir("test_irb_history_windows_") do |tmpdir|
        history_dir = File.join(tmpdir, "history")
        history_file = File.join(history_dir, "irb_history")
        FileUtils.mkdir_p(history_dir)

        with_readonly_attribute(history_dir) do
          assert_nothing_raised do
            File.write(File.join(history_dir, "manual_write"), "ok")
          end

          _output, warning = capture_output do
            run_irb_with_history(history_file)
          end

          assert_equal("", warning)
          assert_equal(<<~HISTORY, File.read(history_file))
            puts 'history_entry'
            exit
          HISTORY
        end
      end
    end

    private

    def with_readonly_attribute(path)
      assert(system("attrib", "+R", windows_path(path)), "failed to set read-only attribute on #{path}")
      yield
    ensure
      system("attrib", "-R", windows_path(path)) if path && File.directory?(path)
    end

    def windows_path(path)
      return path unless File::ALT_SEPARATOR

      path.tr(File::SEPARATOR, File::ALT_SEPARATOR)
    end

    def run_irb_with_history(history_file)
      IRB.init_config(nil)
      IRB.init_error
      IRB.conf[:PROMPT_MODE] = :SIMPLE
      IRB.conf[:SAVE_HISTORY] = 100
      IRB.conf[:HISTORY_FILE] = history_file
      IRB.conf[:USE_PAGER] = false

      input = TestInputMethodWithHistory.new(["puts 'history_entry'", "exit"])
      irb = IRB::Irb.new(IRB::WorkSpace.new(Object.new), input)
      irb.context.return_format = "=> %s\n"
      irb.run(IRB.conf)
    ensure
      TestInputMethodWithHistory::HISTORY.clear
    end
  end
end
