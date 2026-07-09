# frozen_string_literal: true

require "socket"
require "tempfile"
require_relative "helper"

module TestIRB
  class AgentWorkflowTest < IntegrationTestCase
    def test_phase1_prints_instructions_and_exits
      write_ruby <<~'RUBY'
        require "irb"
        puts "BEFORE"
        binding.agent
        puts "AFTER"
      RUBY

      output = run_ruby_file do
        type("should not get here")
      end

      assert_include output, "IRB agent breakpoint hit at"
      assert_include output, "IRB_SOCK_PATH"
      assert_include output, 'require "irb"; binding.agent'
      assert_include output, "BEFORE"
      # exit(0) means AFTER should not print
      assert_not_include output, "AFTER"
    end

    def test_phase2_basic_eval
      write_ruby <<~'RUBY'
        require "irb"
        binding.agent
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
        Potato.new("Russet").instance_eval { binding.agent }
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
        Potato.new.instance_eval { binding.agent }
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, "show_source cook!")
        send_command(sock_path, "exit")
      end

      assert_include output, "def cook!"
    end

    def test_phase2_show_doc_command
      write_ruby <<~'RUBY'
        require "irb"
        binding.agent
      RUBY

      documentation = nil
      run_agent_session do |sock_path|
        documentation = send_command(sock_path, "show_doc Array#each")
        send_command(sock_path, "exit")
      end

      assert_include documentation, "Array#each"
    end

    def test_phase2_source_command_keeps_session_output_policy_and_history
      Tempfile.create(["agent_source", ".rb"]) do |source_file|
        source_file.write(<<~'RUBY')
          history
          edit "missing-agent-file.rb"
          source_value = 21
          source_value * 2
        RUBY
        source_file.flush

        write_ruby <<~RUBY
          require "irb"
          binding.agent
        RUBY

        source_output = nil
        run_agent_session do |sock_path|
          source_output = send_command(sock_path, "source #{source_file.path.dump}")
          send_command(sock_path, "exit")
        end

        assert_include source_output, "=> 42"
        assert_include source_output, source_file.path
        assert_include source_output, "edit launches an interactive program on the host"
      end
    end

    def test_phase2_error_handling
      write_ruby <<~'RUBY'
        require "irb"
        binding.agent
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, "undefined_var")
        send_command(sock_path, "exit")
      end

      assert_include output, "NameError"
    end

    def test_phase2_routes_yaml_fallback_through_the_socket
      write_ruby <<~'RUBY'
        require "irb"
        class BadYaml
          def encode_with(_coder); raise "not serializable"; end
        end
        binding.agent
      RUBY

      response = nil
      run_agent_session do |sock_path|
        send_command(sock_path, "IRB.CurrentContext.inspect_mode = :yaml")
        response = send_command(sock_path, "BadYaml.new")
        send_command(sock_path, "exit")
      end

      assert_match(/\A\(can't dump yaml\. use inspect\)\n=> #<BadYaml:.*>\n\z/, response)
    end

    def test_phase2_multiline_expression
      write_ruby <<~'RUBY'
        require "irb"
        binding.agent
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
        binding.agent
      RUBY

      history = nil
      output = run_agent_session do |sock_path|
        send_command(sock_path, "x = 42")
        send_command(sock_path, "x * 2")
        history = send_command(sock_path, "history")
        send_command(sock_path, "exit")
      end

      assert_include output, "=> 42"
      assert_include output, "=> 84"
      assert_include history, "x = 42"
      assert_include history, "x * 2"
    end

    def test_phase2_resumes_execution_after_exit
      write_ruby <<~'RUBY'
        require "irb"
        puts "BEFORE"
        binding.agent
        puts "AFTER"
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, "exit")
      end

      assert_include output, "BEFORE"
      assert_include output, "AFTER"
    end

    def test_phase2_exit_bang_survives_socket_cleanup_failure
      write_ruby <<~'RUBY'
        require "irb"
        at_exit { puts "AT_EXIT_EXCEPTION=#{$!.class}" }
        puts "BEFORE"
        binding.agent
        puts "AFTER"
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, <<~'RUBY')
          File.singleton_class.prepend(Module.new do
            def unlink(path)
              raise Errno::EACCES, path if path == ENV["IRB_SOCK_PATH"]
              super
            end
          end)
        RUBY
        send_command(sock_path, "exit!")
      end

      assert_include output, "BEFORE"
      assert_include output, "AT_EXIT_EXCEPTION=SystemExit"
      assert_not_include output, "AFTER"
      assert_not_include output, "Permission denied"
    end

    def test_phase2_help_command
      write_ruby <<~'RUBY'
        require "irb"
        binding.agent
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, "help")
        send_command(sock_path, "exit")
      end

      assert_include output, "show_source"
      assert_include output, "ls"
    end

    def test_phase2_ignores_empty_connections
      write_ruby <<~'RUBY'
        require "irb"
        binding.agent
      RUBY

      output = run_agent_session do |sock_path|
        close_connection_without_input(sock_path)
        send_command(sock_path, "1 + 1")
        send_command(sock_path, "exit")
      end

      assert_include output, "=> 2"
    end

    def test_phase2_does_not_capture_other_threads_output
      write_ruby <<~'RUBY'
        require "irb"
        output_thread = Thread.new do
          sleep 0.05
          puts "HOST_THREAD_OUTPUT"
        end
        binding.agent
        output_thread.join
      RUBY

      response = nil
      output = run_agent_session do |sock_path|
        response = send_command(sock_path, "sleep 0.15; 42")
        send_command(sock_path, "exit")
      end

      assert_include response, "=> 42"
      assert_not_include response, "HOST_THREAD_OUTPUT"
      assert_include output, "HOST_THREAD_OUTPUT"
      assert_not_include output, "Switch to inspect mode."
    end

    def test_phase2_does_not_replace_an_active_socket
      write_ruby <<~'RUBY'
        require "irb"
        binding.agent
      RUBY

      second_server_error = nil
      output = run_agent_session do |sock_path|
        second_server_error = send_command(sock_path, <<~'RUBY')
          begin
            IRB::AgentSession::SocketInputMethod.new(ENV.fetch("IRB_SOCK_PATH"))
          rescue => error
            "#{error.class}: #{error.message}"
          end
        RUBY
        send_command(sock_path, "1 + 1")
        send_command(sock_path, "exit")
      end

      assert_include second_server_error, "Errno::EADDRINUSE"
      assert_include output, "=> 2"
    end

    def test_phase2_replaces_a_stale_socket
      write_ruby <<~'RUBY'
        require "irb"
        require "socket"
        stale_server = UNIXServer.new(ENV.fetch("IRB_SOCK_PATH"))
        stale_server.close
        binding.agent
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, "1 + 1")
        send_command(sock_path, "exit")
      end

      assert_include output, "=> 2"
    end

    def test_phase2_preserves_a_replacement_socket_during_cleanup
      write_ruby <<~'RUBY'
        require "irb"
        require "socket"
        binding.agent
        path = ENV.fetch("IRB_SOCK_PATH")
        puts "REPLACEMENT_PRESERVED=#{File.socket?(path)}"
        $replacement_server.close
        File.unlink(path)
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, <<~'RUBY')
          path = ENV.fetch("IRB_SOCK_PATH")
          File.unlink(path)
          $replacement_server = UNIXServer.new(path)
          IRB.irb_exit
        RUBY
      end

      assert_include output, "REPLACEMENT_PRESERVED=true"
    end

    def test_phase2_rejects_commands_that_start_other_interactive_loops
      write_ruby <<~'RUBY'
        require "irb"
        binding.agent
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, "debug")
        send_command(sock_path, "irb")
        send_command(sock_path, "edit")
        send_command(sock_path, "show_doc")
        send_command(sock_path, "exit")
      end

      assert_include output, "debugger commands start a separate interactive console"
      assert_include output, "multi-IRB commands switch between interactive input loops"
      assert_include output, "edit launches an interactive program on the host"
      assert_include output, "interactive RI requires a terminal"
    end

    def test_phase2_restores_irb_configuration
      write_ruby <<~'RUBY'
        require "irb"
        IRB.setup(__FILE__, argv: [])
        previous_context = Object.new
        IRB.conf[:MAIN_CONTEXT] = previous_context
        IRB.conf[:USE_PAGER] = true

        binding.agent

        puts "MAIN_CONTEXT_RESTORED=#{IRB.conf[:MAIN_CONTEXT].equal?(previous_context)}"
        puts "USE_PAGER_RESTORED=#{IRB.conf[:USE_PAGER].inspect}"
      RUBY

      output = run_agent_session do |sock_path|
        send_command(sock_path, "exit")
      end

      assert_include output, "MAIN_CONTEXT_RESTORED=true"
      assert_include output, "USE_PAGER_RESTORED=true"
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
          # Collect PTY output in background; the process produces no stdout
          # until after the IRB session ends (e.g. puts after the breakpoint).
          reader = Thread.new do
            while line = safe_gets(read)
              pty_lines << line
            end
          end

          poll_until { socket_accepting?(sock_path) }

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

    def close_connection_without_input(sock_path)
      sock = UNIXSocket.new(sock_path)
      sock.close_write
      sock.read
    ensure
      sock&.close
    end

    def socket_accepting?(sock_path)
      sock = UNIXSocket.new(sock_path)
      true
    rescue Errno::ECONNREFUSED, Errno::ENOENT
      false
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
