# frozen_string_literal: true

require 'socket'
require 'stringio'

module IRB
  # A request/response server for agent-driven IRB sessions over a Unix socket
  # (experimental).
  #
  # When <tt>binding.agent</tt> is called, the behavior depends on
  # the +IRB_SOCK_PATH+ environment variable:
  #
  # - *Not set* (Phase 1 — discovery): prints instructions explaining how to
  #   start a debug session, then calls <tt>exit(0)</tt>. This lets the agent
  #   see the instructions before the process terminates.
  #
  # - *Set* (Phase 2 — debug session): starts a Unix socket server at the
  #   given path. The server accepts one connection at a time in a loop. Each
  #   connection is a single request: the client sends Ruby code (or an IRB
  #   command), closes its write end, and reads back the result. The IRB session
  #   state persists across requests. Sending +exit+ ends the loop and resumes
  #   execution of the host program.
  #
  # == Example agent workflow
  #
  #   # 1. Run the app — hits breakpoint, prints instructions, exits:
  #   $ ruby app.rb
  #
  #   # 2. Re-run in background with a socket path:
  #   $ IRB_SOCK_PATH=/tmp/irb-debug.sock ruby app.rb &
  #
  #   # 3. Send commands (one per connection):
  #   $ ruby -e 'require "socket"; s = UNIXSocket.new("/tmp/irb-debug.sock"); s.puts "ls"; s.close_write; puts s.read; s.close'
  #   $ ruby -e 'require "socket"; s = UNIXSocket.new("/tmp/irb-debug.sock"); s.puts "exit"; s.close_write; puts s.read; s.close'
  #
  class RemoteServer
    def initialize(binding_context, sock_path:)
      @binding_context = binding_context
      @sock_path = sock_path
    end

    class StringInput < InputMethod
      def initialize(str)
        super()
        @io = StringIO.new(str)
      end

      def gets
        @io.gets
      end

      def eof?
        @io.eof?
      end

      def encoding
        Encoding::UTF_8
      end
    end

    def run
      File.delete(@sock_path) rescue Errno::ENOENT # rubocop:disable Style/RescueModifier

      server = UNIXServer.new(@sock_path)
      File.chmod(0600, @sock_path)

      original_stdout = $stdout

      IRB.conf[:USE_PAGER] = false

      binding_irb = create_irb
      IRB.conf[:MAIN_CONTEXT] = binding_irb.context

      begin
        loop do
          client = server.accept
          input = client.read
          break if input.nil? || input.empty?

          binding_irb.context.io = StringInput.new(input)

          not_exited = catch(:IRB_EXIT) do
            begin
              $stdout = client
              binding_irb.eval_input
            ensure
              $stdout = original_stdout
            end
            :not_exited
          end

          client.close rescue nil # rubocop:disable Style/RescueModifier

          break unless not_exited == :not_exited
        end
      ensure
        $stdout = original_stdout
        server&.close
        File.delete(@sock_path) rescue Errno::ENOENT # rubocop:disable Style/RescueModifier
      end
    end

    private

    def create_irb
      workspace = IRB::WorkSpace.new(@binding_context)
      irb = IRB::Irb.new(workspace, StringInput.new(""), from_binding: true)
      irb.context.irb_path = File.expand_path(@binding_context.source_location[0])
      irb.context.verbose = false
      irb.context.newline_before_multiline_output = false
      irb
    end

    class << self
      def print_instructions(binding_context)
        file, line = binding_context.source_location
        method_name = binding_context.eval("__method__") rescue nil # rubocop:disable Style/RescueModifier
        location = method_name ? "#{file}:#{line} in `#{method_name}`" : "#{file}:#{line}"

        $stdout.puts <<~MSG
          ══════════════════════════════════════════════════════════
          IRB agent breakpoint hit at #{location}

          No IRB_SOCK_PATH set — exiting without starting a debug session.

          Add breakpoints with: require "irb"; binding.agent

          To debug this breakpoint:

            1. Run the app in the BACKGROUND with a socket path:

                 IRB_SOCK_PATH=/tmp/irb-UNIQUE_ID.sock <your command>

               The process will block waiting for a connection.

            2. Wait for the socket file to appear:

                 ls /tmp/irb-UNIQUE_ID.sock

            3. Send commands to the socket with FOREGROUND commands:

                 ruby -e 'require "socket"; s = UNIXSocket.new("/tmp/irb-UNIQUE_ID.sock"); s.puts "help"; s.close_write; puts s.read; s.close'

               Each invocation sends one command and prints the result.
               The IRB session persists between invocations.

               Examples:
                 ... s.puts "ls"; s.close_write              # list methods and variables
                 ... s.puts "show_source foo"; s.close_write  # see source of a method
                 ... s.puts "@name"; s.close_write            # inspect a variable
                 ... s.puts "exit"; s.close_write             # end session, resume app

          ══════════════════════════════════════════════════════════
        MSG
        $stdout.flush
      end
    end
  end
end
