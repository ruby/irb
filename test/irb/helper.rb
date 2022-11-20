require "test/unit"
begin
  require_relative "../lib/helper"
rescue LoadError # ruby/ruby defines helpers differently
end
require "socket"
require "pty"

module IRB
  class InputMethod; end
end

module TestIRB
  class TestCase < Test::Unit::TestCase
    class TestInputMethod < ::IRB::InputMethod
      attr_reader :list, :line_no

      def initialize(list = [])
        super("test")
        @line_no = 0
        @list = list
      end

      def gets
        @list[@line_no]&.tap {@line_no += 1}
      end

      def eof?
        @line_no >= @list.size
      end

      def encoding
        Encoding.default_external
      end

      def reset
        @line_no = 0
      end
    end

    def save_encodings
      @default_encoding = [Encoding.default_external, Encoding.default_internal]
      @stdio_encodings = [STDIN, STDOUT, STDERR].map {|io| [io.external_encoding, io.internal_encoding] }
    end

    def restore_encodings
      EnvUtil.suppress_warning do
        Encoding.default_external, Encoding.default_internal = *@default_encoding
        [STDIN, STDOUT, STDERR].zip(@stdio_encodings) do |io, encs|
          io.set_encoding(*encs)
        end
      end
    end

    def without_rdoc(&block)
      ::Kernel.send(:alias_method, :old_require, :require)

      ::Kernel.define_method(:require) do |name|
        raise LoadError, "cannot load such file -- rdoc (test)" if name.match?("rdoc") || name.match?(/^rdoc\/.*/)
        ::Kernel.send(:old_require, name)
      end

      yield
    ensure
      begin
        require_relative "../lib/envutil"
      rescue LoadError # ruby/ruby defines EnvUtil differently
      end
      EnvUtil.suppress_warning { ::Kernel.send(:alias_method, :require, :old_require) }
    end
  end

  # Ported from DEBUGGER__::AssertionHelpers
  module AssertionHelpers
    def assert_line_num(expected)
      case get_target_ui
      when 'terminal'
        @scenario.push(Proc.new { |test_info|
          msg = "Expected line number to be #{expected.inspect}, but was #{test_info.internal_info['line']}\n"

          assert_block(FailureMessage.new { create_message(msg, test_info) }) do
            expected == test_info.internal_info['line']
          end
        })
      when 'vscode'
        send_request 'stackTrace',
                      threadId: 1,
                      startFrame: 0,
                      levels: 20
        res = find_crt_dap_response
        failure_msg = FailureMessage.new{create_protocol_message "result:\n#{JSON.pretty_generate res}"}
        result = res.dig(:body, :stackFrames, 0, :line)
        assert_equal expected, result, failure_msg
      when 'chrome'
        failure_msg = FailureMessage.new{create_protocol_message "result:\n#{JSON.pretty_generate @crt_frames}"}
        result = @crt_frames.dig(0, :location, :lineNumber) + 1
        assert_equal expected, result, failure_msg
      else
        raise 'Invalid environment variable'
      end
    end

    def assert_line_text(text)
      @scenario.push(Proc.new { |test_info|
        result = collect_recent_backlog(test_info.last_backlog)

        expected =
          case text
          when Array
            case text.first
            when String
              text.map { |s| Regexp.escape(s) }.join
            when Regexp
              Regexp.compile(text.map(&:source).join('.*'), Regexp::MULTILINE)
            end
          when String
            Regexp.escape(text)
          when Regexp
            text
          else
            raise "Unknown expectation value: #{text.inspect}"
          end

        msg = "Expected to include `#{expected.inspect}` in\n(\n#{result})\n"

        assert_block(FailureMessage.new { create_message(msg, test_info) }) do
          result.match? expected
        end
      })
    end

    def assert_no_line_text(text)
      @scenario.push(Proc.new { |test_info|
        result = collect_recent_backlog(test_info.last_backlog)
        if text.is_a?(String)
          expected = Regexp.escape(text)
        else
          expected = text
        end
        msg = "Expected not to include `#{expected.inspect}` in\n(\n#{result})\n"

        assert_block(FailureMessage.new { create_message(msg, test_info) }) do
          !result.match? expected
        end
      })
    end

    def assert_debuggee_line_text text
      @scenario.push(Proc.new {|test_info|
        next if test_info.mode == 'LOCAL'

        log = test_info.remote_info.debuggee_backlog.join
        msg = "Expected to include `#{text.inspect}` in\n(\n#{log})\n"

        assert_block(FailureMessage.new{create_message(msg, test_info)}) do
          log.match? text
        end
      })
    end

    def assert_block msg
      if multithreaded_test?
        # test-unit doesn't support multi thread
        # FYI: test-unit/test-unit#204
        throw :fail, msg.to_s unless yield
      else
        super
      end
    end

    private

    def collect_recent_backlog(last_backlog)
      last_backlog[1..].join
    end
  end

  # Ported from DEBUGGER__::FailureMessage
  class FailureMessage
    def initialize &block
      @msg = nil
      @create_msg = block
    end

    def to_s
      return @msg if @msg

      @msg = @create_msg.call
    end
  end

  # Ported from DEBUGGER__::TestCase
  class IsolatedTestCase < Test::Unit::TestCase
    TestInfo = Struct.new(:queue, :mode, :prompt_pattern, :remote_info,
                          :backlog, :last_backlog, :internal_info, :failed_process)

    RemoteInfo = Struct.new(:r, :w, :pid, :sock_path, :port, :reader_thread, :debuggee_backlog)

    MULTITHREADED_TEST = !(%w[1 true].include? ENV['RUBY_DEBUG_TEST_DISABLE_THREADS'])

    include AssertionHelpers

    def setup
      @temp_file = nil
    end

    def teardown
      remove_temp_file
    end

    def temp_file_path
      @temp_file.path
    end

    def remove_temp_file
      File.unlink(@temp_file) if @temp_file
      @temp_file = nil
    end

    def write_temp_file(program)
      @temp_file = Tempfile.create(%w[debug- .rb])
      @temp_file.write(program)
      @temp_file.close
    end

    def with_extra_tempfile(*additional_words)
      name = SecureRandom.hex(5) + additional_words.join

      t = Tempfile.create([name, '.rb']).tap do |f|
        f.write(extra_file)
        f.close
      end
      yield t
    ensure
      File.unlink t if t
    end

    LINE_NUMBER_REGEX = /^\s*\d+\| ?/

    def strip_line_num(str)
      str.gsub(LINE_NUMBER_REGEX, '')
    end

    def check_line_num!(program)
      unless program.match?(LINE_NUMBER_REGEX)
        new_program = program_with_line_numbers(program)
        raise "line numbers are required in test script. please update the script with:\n\n#{new_program}"
      end
    end

    def program_with_line_numbers(program)
      lines = program.split("\n")
      lines_with_number = lines.map.with_index do |line, i|
        "#{'%4d' % (i+1)}| #{line}"
      end

      lines_with_number.join("\n")
    end

    def type(command)
      @scenario.push(command)
    end

    def multithreaded_test?
      Thread.current[:is_subthread]
    end

    ASK_CMD = %w[quit q delete del kill undisplay].freeze

    def debug_print msg
      print msg if ENV['RUBY_DEBUG_TEST_DEBUG_MODE']
    end

    RUBY = ENV['RUBY'] || RbConfig.ruby

    TIMEOUT_SEC = (ENV['RUBY_DEBUG_TIMEOUT_SEC'] || 10).to_i

    def get_target_ui
      ENV['RUBY_DEBUG_TEST_UI']
    end

    private

    def wait_pid pid, sec
      total_sec = 0.0
      wait_sec = 0.001 # 1ms

      while total_sec < sec
        if Process.waitpid(pid, Process::WNOHANG) == pid
          return true
        end
        sleep wait_sec
        total_sec += wait_sec
        wait_sec *= 2
      end

      false
    end

    def kill_safely pid, name, test_info
      return if wait_pid pid, 3

      test_info.failed_process = name

      Process.kill :TERM, pid
      return if wait_pid pid, 0.2

      Process.kill :KILL, pid
      Process.waitpid(pid)
    rescue Errno::EPERM, Errno::ESRCH
    end

    def check_error(error, test_info)
      if error_index = test_info.last_backlog.index { |l| l.match?(error) }
        assert_block(create_message("Debugger terminated because of: #{test_info.last_backlog[error_index..-1].join}", test_info)) { false }
      end
    end

    def kill_remote_debuggee test_info
      return unless r = test_info.remote_info

      r.reader_thread.kill
      r.r.close
      r.w.close
      kill_safely r.pid, :remote, test_info
    end

    def setup_remote_debuggee(cmd)
      homedir = defined?(self.class.pty_home_dir) ? self.class.pty_home_dir : ENV['HOME']

      remote_info = DEBUGGER__::TestCase::RemoteInfo.new(*PTY.spawn({'HOME' => homedir}, cmd))
      remote_info.r.read(1) # wait for the remote server to boot up
      remote_info.debuggee_backlog = []

      remote_info.reader_thread = Thread.new(remote_info) do |info|
        while data = info.r.gets
          info.debuggee_backlog << data
        end
      rescue Errno::EIO
      end
      remote_info
    end

    $ruby_debug_test_num = 0

    def setup_unix_domain_socket_remote_debuggee
      sock_path = DEBUGGER__.create_unix_domain_socket_name + "-#{$ruby_debug_test_num += 1}"
      remote_info = setup_remote_debuggee("#{RDBG_EXECUTABLE} -O --sock-path=#{sock_path} #{temp_file_path}")
      remote_info.sock_path = sock_path

      Timeout.timeout(TIMEOUT_SEC) do
        sleep 0.1 while !File.exist?(sock_path) && Process.kill(0, remote_info.pid)
      end

      remote_info
    end

    # search free port by opening server socket with port 0
    Socket.tcp_server_sockets(0).tap do |ss|
      TCPIP_PORT = ss.first.local_address.ip_port
    end.each{|s| s.close}

    def setup_tcpip_remote_debuggee
      remote_info = setup_remote_debuggee("#{RDBG_EXECUTABLE} -O --port=#{TCPIP_PORT} -- #{temp_file_path}")
      remote_info.port = TCPIP_PORT
      remote_info
    end

    # Debuggee sometimes sends msgs such as "out [1, 5] in ...".
    # This http request method is for ignoring them.
    def get_request host, port, path
      Timeout.timeout(TIMEOUT_SEC) do
        Socket.tcp(host, port){|sock|
          sock.print "GET #{path} HTTP/1.1\r\n"
          sock.close_write
          loop do
            case header = sock.gets
            when /Content-Length: (\d+)/
              b = sock.read(2)
              raise b.inspect unless b == "\r\n"

              l = sock.read $1.to_i
              return JSON.parse l, symbolize_names: true
            end
          end
        }
      end
    end
  end

  # Ported from DEBUGGER__::ConsoleTestCase
  class ConsoleTestCase < IsolatedTestCase
    nr = ENV['RUBY_DEBUG_TEST_NO_REMOTE']
    NO_REMOTE = true

    if !NO_REMOTE
      warn "Tests on local and remote. You can disable remote tests with RUBY_DEBUG_TEST_NO_REMOTE=1."
    end

    # CIs usually doesn't allow overriding the HOME path
    # we also don't need to worry about adding or being affected by ~/.rdbgrc on CI
    # so we can just use the original home page there
    USE_TMP_HOME =
      !ENV["CI"] ||
      begin
        pwd = Dir.pwd
        ruby = ENV['RUBY'] || RbConfig.ruby
        home_cannot_change = false
        PTY.spawn({ "HOME" => pwd }, ruby, '-e', 'puts ENV["HOME"]') do |r,|
          home_cannot_change = r.gets.chomp != pwd
        end
        home_cannot_change
      end

    class << self
      attr_reader :pty_home_dir

      def startup
        @pty_home_dir =
          if USE_TMP_HOME
            Dir.mktmpdir
          else
            Dir.home
          end
      end

      def shutdown
        if USE_TMP_HOME
          FileUtils.remove_entry @pty_home_dir
        end
      end
    end

    def pty_home_dir
      self.class.pty_home_dir
    end

    def create_message fail_msg, test_info
      debugger_msg = <<~DEBUGGER_MSG.chomp
        --------------------
        | Debugger Session |
        --------------------

        > #{test_info.backlog.join('> ')}
      DEBUGGER_MSG

      debuggee_msg =
        if test_info.mode != 'LOCAL'
          <<~DEBUGGEE_MSG.chomp
            --------------------
            | Debuggee Session |
            --------------------

            > #{test_info.remote_info.debuggee_backlog.join('> ')}
          DEBUGGEE_MSG
        end

      failure_msg = <<~FAILURE_MSG.chomp
        -------------------
        | Failure Message |
        -------------------

        #{fail_msg} on #{test_info.mode} mode
      FAILURE_MSG

      <<~MSG.chomp

        #{debugger_msg}

        #{debuggee_msg}

        #{failure_msg}
      MSG
    end

    def debug_code(program, remote: true, &test_steps)
      Timeout.timeout(30) do
        prepare_test_environment(program, test_steps) do
          if remote && !NO_REMOTE && MULTITHREADED_TEST
            begin
              th = [
                new_thread { debug_code_on_local },
              ]

              th.each do |t|
                if fail_msg = t.join.value
                  th.each(&:kill)
                  flunk fail_msg
                end
              end
            rescue Exception => e
              th.each(&:kill)
              flunk "#{e.class.name}: #{e.message}"
            end
          elsif remote && !NO_REMOTE
            debug_code_on_local
          else
            debug_code_on_local
          end
        end
      end
    end

    def run_test_scenario cmd, test_info
      PTY.spawn({ "HOME" => pty_home_dir }, cmd) do |read, write, pid|
        test_info.backlog = []
        test_info.last_backlog = []
        begin
          Timeout.timeout(TIMEOUT_SEC) do
            while (line = read.gets)
              debug_print line
              test_info.backlog.push(line)
              test_info.last_backlog.push(line)

              case line.chomp
              when /INTERNAL_INFO:\s(.*)/
                # INTERNAL_INFO shouldn't be pushed into backlog and last_backlog
                test_info.backlog.pop
                test_info.last_backlog.pop

                test_info.internal_info = JSON.parse(Regexp.last_match(1))
                assertion = []
                is_ask_cmd = false

                loop do
                  assert_block(FailureMessage.new { create_message "Expected the REPL prompt to finish", test_info }) { !test_info.queue.empty? }
                  cmd = test_info.queue.pop

                  case cmd.to_s
                  when /Proc/
                    if is_ask_cmd
                      assertion.push cmd
                    else
                      cmd.call test_info
                    end
                  when /flunk_finish/
                    cmd.call test_info
                  when *ASK_CMD
                    write.puts cmd
                    is_ask_cmd = true
                  else
                    break
                  end
                end

                write.puts(cmd)
                test_info.last_backlog.clear
              when %r{\[y/n\]}i
                assertion.each do |a|
                  a.call test_info
                end
              when test_info.prompt_pattern
                # check if the previous command breaks the debugger before continuing
                check_error(/REPL ERROR/, test_info)
              end
            end

            check_error(/DEBUGGEE Exception/, test_info)
            assert_empty_queue test_info
          end
        # result of `gets` return this exception in some platform
        # https://github.com/ruby/ruby/blob/master/ext/pty/pty.c#L729-L736
        rescue Errno::EIO => e
          check_error(/DEBUGGEE Exception/, test_info)
          assert_empty_queue test_info, exception: e
        rescue Timeout::Error
          assert_block(create_message("TIMEOUT ERROR (#{TIMEOUT_SEC} sec)", test_info)) { false }
        ensure
          kill_remote_debuggee test_info
          # kill debug console process
          read.close
          write.close
          kill_safely pid, :debugger, test_info
          if name = test_info.failed_process
            assert_block(create_message("Expected the #{name} program to finish", test_info)) { false }
          end
        end
      end
    end

    def prepare_test_environment(program, test_steps, &block)
      ENV['RUBY_DEBUG_NO_COLOR'] = 'true'
      ENV['RUBY_DEBUG_TEST_UI'] = 'terminal'
      ENV['RUBY_DEBUG_NO_RELINE'] = 'true'
      ENV['RUBY_DEBUG_HISTORY_FILE'] = ''

      write_temp_file(strip_line_num(program))
      @scenario = []
      test_steps.call
      @scenario.freeze
      inject_lib_to_load_path

      block.call

      check_line_num!(program)

      assert true
    end

    # use this to start a debug session with the test program
    def manual_debug_code(program)
      print("[Starting a Debug Session with @#{caller.first}]\n")
      write_temp_file(strip_line_num(program))
      remote_info = setup_unix_domain_socket_remote_debuggee

      Timeout.timeout(TIMEOUT_SEC) do
        while !File.exist?(remote_info.sock_path)
          sleep 0.1
        end
      end

      DEBUGGER__::Client.new([socket_path]).connect
    ensure
      kill_remote_debuggee remote_info
    end

    private def debug_code_on_local
      test_info = TestInfo.new(dup_scenario, 'LOCAL', /\(rdbg\)/)
      cmd = "#{RUBY} #{temp_file_path}"
      run_test_scenario cmd, test_info
    end

    private def debug_code_on_unix_domain_socket
      test_info = TestInfo.new(dup_scenario, 'UNIX Domain Socket', /\(rdbg:remote\)/)
      test_info.remote_info = setup_unix_domain_socket_remote_debuggee
      cmd = "#{RDBG_EXECUTABLE} -A #{test_info.remote_info.sock_path}"
      run_test_scenario cmd, test_info
    end

    private def debug_code_on_tcpip
      test_info = TestInfo.new(dup_scenario, 'TCP/IP', /\(rdbg:remote\)/)
      test_info.remote_info = setup_tcpip_remote_debuggee
      cmd = "#{RDBG_EXECUTABLE} -A #{test_info.remote_info.port}"
      run_test_scenario cmd, test_info
    end

    def run_ruby program, options: nil, &test_steps
      prepare_test_environment(program, test_steps) do
        test_info = TestInfo.new(dup_scenario, 'LOCAL', /\(rdbg\)/)
        cmd = "#{RUBY} #{options} -- #{temp_file_path}"
        run_test_scenario cmd, test_info
      end
    end

    def run_rdbg program, options: nil, rubyopt: nil, &test_steps
      prepare_test_environment(program, test_steps) do
        test_info = TestInfo.new(dup_scenario, 'LOCAL', /\(rdbg\)/)
        cmd = "#{RDBG_EXECUTABLE} #{options} -- #{temp_file_path}"
        cmd = "RUBYOPT=#{rubyopt} #{cmd}" if rubyopt
        run_test_scenario cmd, test_info
      end
    end

    def dup_scenario
      @scenario.each_with_object(Queue.new){ |e, q| q << e }
    end

    def new_thread &block
      Thread.new do
        Thread.current[:is_subthread] = true
        catch(:fail) do
          block.call
        end
      end
    end

    def inject_lib_to_load_path
      ENV['RUBYOPT'] = "-I #{__dir__}/../../lib"
    end

    def assert_empty_queue test_info, exception: nil
      message = "Expected all commands/assertions to be executed. Still have #{test_info.queue.length} left."
      if exception
        message += "\nAssociated exception: #{exception.class} - #{exception.message}" +
                   exception.backtrace.map{|l| "  #{l}\n"}.join
      end
      assert_block(FailureMessage.new { create_message message, test_info }) { test_info.queue.empty? }
    end
  end
end
