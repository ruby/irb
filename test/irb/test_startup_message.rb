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

    def test_banner_appears_when_stdin_is_a_tty
      output = run_irb_with_tty

      assert_match(/v#{Regexp.escape(IRB::VERSION)}/, output)
    end

    def test_banner_does_not_appear_when_stdin_is_not_a_tty
      output = run_irb_without_tty

      assert_not_match(/v#{Regexp.escape(IRB::VERSION)}/, output)
    end

    private

    def irb_command
      [EnvUtil.rubybin, "-I", LIB, File.expand_path("../../exe/irb", __dir__), "-f"]
    end

    def irb_envs(tmp_dir)
      { "TERM" => "dumb", "HOME" => tmp_dir, "XDG_CONFIG_HOME" => tmp_dir, "IRBRC" => nil }
    end

    def run_irb_with_tty
      lines = []

      Dir.mktmpdir do |tmp_dir|
        PTY.spawn(irb_envs(tmp_dir), *irb_command) do |read, write, pid|
          write.puts "exit"

          Timeout.timeout(TIMEOUT_SEC) do
            while line = safe_gets(read)
              lines << line
            end
          end
        ensure
          read.close
          write.close
          kill_safely(pid)
        end
      end

      lines.join
    end

    def run_irb_without_tty
      Dir.mktmpdir do |tmp_dir|
        IO.popen(irb_envs(tmp_dir), irb_command, "r+", err: [:child, :out]) do |io|
          io.puts "exit"
          io.close_write
          io.read
        end
      end
    end
  end
end
