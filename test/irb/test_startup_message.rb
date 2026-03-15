# frozen_string_literal: true

require "irb"

require_relative "helper"

module TestIRB
  class StartupMessageTest < TestCase
    def test_display_includes_version_info
      output, = capture_output { IRB::StartupMessage.display }

      assert_match(/IRB/, output)
      assert_match(/v#{Regexp.escape(IRB::VERSION)}/, output)
      assert_match(/Ruby #{Regexp.escape(RUBY_VERSION)}/, output)
    end

    def test_display_includes_a_tip
      output, = capture_output { IRB::StartupMessage.display }

      # Strip ANSI codes for comparison since tips have colorized quoted parts
      plain = output.gsub(/\e\[\d+m/, "")
      assert(
        IRB::StartupMessage::TIPS.any? { |tip| plain.include?(tip) },
        "Expected output to include one of the tips"
      )
    end

    def test_display_includes_working_directory
      output, = capture_output { IRB::StartupMessage.display }

      assert_match(/#{Regexp.escape(File.basename(Dir.pwd))}/, output)
    end

    def test_short_pwd_replaces_home_with_tilde
      Dir.mktmpdir do |tmpdir|
        tmpdir = File.realpath(tmpdir)
        original_home = ENV['HOME']
        original_dir = Dir.pwd
        ENV['HOME'] = tmpdir
        Dir.chdir(tmpdir)

        result = IRB::StartupMessage.send(:short_pwd)
        assert_equal "~", result

        subdir = File.join(tmpdir, "projects")
        Dir.mkdir(subdir)
        Dir.chdir(subdir)

        result = IRB::StartupMessage.send(:short_pwd)
        assert_equal "~/projects", result
      ensure
        ENV['HOME'] = original_home
        Dir.chdir(original_dir)
      end
    end
  end

  class StartupMessageIntegrationTest < IntegrationTestCase
    def test_banner_does_not_appear_on_binding_irb
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "exit"
      end

      assert_not_match(/v#{Regexp.escape(IRB::VERSION)}/, output)
    end
  end
end
