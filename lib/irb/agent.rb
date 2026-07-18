# frozen_string_literal: true

require "socket"

module IRB
  # A stateful IRB session for agents, transported over a Unix socket.
  class AgentSession
    def initialize(binding_context, sock_path:)
      @binding_context = binding_context
      @sock_path = sock_path
    end

    def run
      input = SocketInputMethod.new(@sock_path)
      binding_irb = create_irb(input)
      binding_irb.run(IRB.conf)
      binding_irb.debug_break
    ensure
      begin
        input&.close
      rescue IOError, SystemCallError
        nil
      end
    end

    private

    def create_irb(input)
      workspace = IRB::WorkSpace.new(@binding_context)
      irb = IRB::Irb.new(workspace, input, from_binding: true, verbose: false)
      irb.context.irb_path = File.expand_path(@binding_context.source_location[0])
      irb.context.newline_before_multiline_output = false
      irb
    end

    # One client connection is one complete IRB request. The client half-closes
    # its write side, then reads until this input method closes the response.
    class SocketInputMethod < IRB::InputMethod
      def initialize(sock_path)
        super()
        @sock_path = sock_path
        @history = []
        @server = bind_server
      end

      def gets
        close_client

        loop do
          @client = @server.accept
          input = @client.read
          if input.empty?
            close_client
            next
          end

          entry = input.chomp
          @history << entry unless entry.empty? || entry == @history.last
          return input
        end
      end

      def check_termination
        # Returning an entire request from #gets gives IRB one complete input,
        # including multiline expressions, without terminal-driven prompting.
      end

      def encoding
        Encoding::UTF_8
      end

      def history
        @history
      end

      def output
        @client || $stdout
      end

      def tty?
        false
      end

      def remote?
        true
      end

      def inspect
        "AgentSocketInputMethod"
      end

      def command_unavailable_reason(command_class, arg)
        if command_class <= IRB::Command::Debug
          "debugger commands start a separate interactive console"
        elsif command_class <= IRB::Command::MultiIRBCommand
          "multi-IRB commands switch between interactive input loops"
        elsif command_class == IRB::Command::Edit
          "edit launches an interactive program on the host"
        elsif command_class == IRB::Command::ShowDoc && arg.strip.empty?
          "interactive RI requires a terminal; pass a documentation target instead"
        end
      end

      def write(*args)
        safely { output.write(*args) }
      end

      def print(*args)
        safely { output.print(*args) }
      end

      def printf(*args)
        safely { output.printf(*args) }
      end

      def puts(*args)
        safely { output.puts(*args) }
      end

      def warn(*messages, **_kwargs)
        puts(*messages)
      end

      def flush
        safely { output.flush }
      end

      def close
        close_client
      ensure
        begin
          close_server
        ensure
          remove_owned_socket
        end
      end

      private

      def bind_server
        retries = 0

        begin
          server = UNIXServer.new(@sock_path)
        rescue Errno::EADDRINUSE
          raise if retries == 1

          remove_stale_socket
          retries += 1
          retry
        end

        @socket_identity = socket_identity
        File.chmod(0600, @sock_path)
        server
      rescue
        begin
          server&.close
        rescue IOError, SystemCallError
          nil
        end
        remove_owned_socket
        raise
      end

      def remove_stale_socket
        stale_identity = socket_identity
        raise Errno::EADDRINUSE, "IRB agent socket path is not a socket: #{@sock_path}" unless stale_identity[:socket]

        if active_socket?
          raise Errno::EADDRINUSE, "IRB agent socket is already in use: #{@sock_path}"
        end

        current_identity = socket_identity
        return unless same_socket?(stale_identity, current_identity)

        File.unlink(@sock_path)
      rescue Errno::ENOENT
        nil
      end

      def active_socket?
        socket = UNIXSocket.new(@sock_path)
        true
      rescue Errno::ECONNREFUSED, Errno::ENOENT
        false
      ensure
        socket&.close
      end

      def socket_identity
        stat = File.lstat(@sock_path)
        { device: stat.dev, inode: stat.ino, socket: stat.socket? }
      end

      def same_socket?(left, right)
        left[:device] == right[:device] && left[:inode] == right[:inode]
      end

      def remove_owned_socket
        return unless @socket_identity

        current_identity = socket_identity
        File.unlink(@sock_path) if current_identity[:socket] && same_socket?(@socket_identity, current_identity)
      rescue SystemCallError
        nil
      ensure
        @socket_identity = nil
      end

      def close_client
        client = @client
        @client = nil
        client&.close
      rescue IOError, SystemCallError
        nil
      end

      def close_server
        server = @server
        @server = nil
        server&.close
      rescue IOError, SystemCallError
        nil
      end

      def safely
        yield
      rescue Errno::EPIPE, IOError
        nil
      end
    end
  end
end
