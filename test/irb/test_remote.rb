# frozen_string_literal: true

require "socket"
require "tempfile"
require_relative "helper"

module TestIRB
  class RemoteTest < IntegrationTestCase
    def test_phase1_prints_instructions_and_exits
      write_ruby <<~'RUBY'
        require "irb"
        puts "BEFORE"
        binding.irb(agent: true)
        puts "AFTER"
      RUBY

      output = run_ruby_file do
        type("should not get here")
      end

      assert_include output, "IRB agent breakpoint hit at"
      assert_include output, "IRB_SOCK_PATH"
      assert_include output, "BEFORE"
      # exit(0) means AFTER should not print
      assert_not_include output, "AFTER"
    end

    def test_phase2_basic_eval
      write_ruby <<~'RUBY'
        require "irb"
        binding.irb(agent: true)
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, "1 + 1")
        send_command(sock_path, "exit")
      end

      assert_include output, "=> 2"
    end

    def test_phase2_ls_command
      write_ruby <<~'RUBY'
        require "irb"
        class Potato
          attr_accessor :name
          def initialize(name); @name = name; end
        end
        Potato.new("Russet").instance_eval { binding.irb(agent: true) }
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, "ls")
        send_command(sock_path, "exit")
      end

      assert_include output, "name"
      assert_include output, "@name"
    end

    def test_phase2_show_source_command
      write_ruby <<~'RUBY'
        require "irb"
        class Potato
          def cook!; "done"; end
        end
        Potato.new.instance_eval { binding.irb(agent: true) }
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, "show_source cook!")
        send_command(sock_path, "exit")
      end

      assert_include output, "def cook!"
    end

    def test_phase2_error_handling
      write_ruby <<~'RUBY'
        require "irb"
        binding.irb(agent: true)
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, "undefined_var")
        send_command(sock_path, "exit")
      end

      assert_include output, "NameError"
    end

    def test_phase2_multiline_expression
      write_ruby <<~'RUBY'
        require "irb"
        binding.irb(agent: true)
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, "def double(x)\n  x * 2\nend")
        send_command(sock_path, "double(21)")
        send_command(sock_path, "exit")
      end

      assert_include output, "=> :double"
      assert_include output, "=> 42"
    end

    def test_phase2_session_state_persists
      write_ruby <<~'RUBY'
        require "irb"
        binding.irb(agent: true)
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, "x = 42")
        send_command(sock_path, "x * 2")
        send_command(sock_path, "exit")
      end

      assert_include output, "=> 42"
      assert_include output, "=> 84"
    end

    def test_phase2_resumes_execution_after_exit
      write_ruby <<~'RUBY'
        require "irb"
        puts "BEFORE"
        binding.irb(agent: true)
        puts "AFTER"
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, "exit")
      end

      assert_include output, "BEFORE"
      assert_include output, "AFTER"
    end

    def test_phase2_help_command
      write_ruby <<~'RUBY'
        require "irb"
        binding.irb(agent: true)
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, "help")
        send_command(sock_path, "exit")
      end

      assert_include output, "show_source"
      assert_include output, "ls"
    end

    private

    def run_agent_session(timeout: TIMEOUT_SEC)
      cmd = [EnvUtil.rubybin, "-I", LIB, @ruby_file.to_path]
      tmp_dir = Dir.mktmpdir
      sock_path = File.join(tmp_dir, "irb-test.sock")
      pty_lines = []
      @command_output = +""

      @envs["HOME"] ||= tmp_dir
      @envs["XDG_CONFIG_HOME"] ||= tmp_dir
      @envs["IRBRC"] = nil unless @envs.key?("IRBRC")

      envs_for_spawn = { 'TERM' => 'dumb', 'IRB_SOCK_PATH' => sock_path }.merge(@envs)

      PTY.spawn(envs_for_spawn, *cmd) do |read, write, pid|
        Timeout.timeout(timeout) do
          # Collect PTY output in background — the process produces no stdout
          # until after the IRB session ends (e.g. puts after the breakpoint).
          reader = Thread.new do
            while line = safe_gets(read)
              pty_lines << line
            end
          end

          poll_until { File.exist?(sock_path) }

          yield sock_path

          reader.join(timeout)
        end
      ensure
        read.close
        write.close
        kill_safely(pid)
      end

      pty_lines.join + @command_output
    rescue Timeout::Error
      message = <<~MSG
        Test timed out.

        #{'=' * 30} PTY OUTPUT #{'=' * 30}
          #{pty_lines.map { |l| "  #{l}" }.join}
        #{'=' * 27} COMMAND OUTPUT #{'=' * 27}
          #{@command_output}
        #{'=' * 27} END #{'=' * 27}
      MSG
      assert_block(message) { false }
    ensure
      FileUtils.remove_entry tmp_dir
    end

    def send_command(sock_path, cmd)
      sock = UNIXSocket.new(sock_path)
      sock.puts cmd
      sock.close_write
      result = sock.read
      @command_output << result
      result
    ensure
      sock&.close
    end

    def poll_until(timeout: TIMEOUT_SEC, interval: 0.05)
      deadline = Time.now + timeout
      until yield
        raise Timeout::Error, "poll_until timed out" if Time.now > deadline
        sleep interval
      end
    end
  end
end
