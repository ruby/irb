# frozen_string_literal: true

module IRB
  # The implementation of this class is borrowed from RDoc's lib/rdoc/ri/driver.rb.
  # Please do NOT use this class directly outside of IRB.
  class Pager
    PAGE_COMMANDS = [ENV['RI_PAGER'], ENV['PAGER'], 'less', 'more'].compact.uniq

    # Maximum size of a single cell in terminal
    # Assumed worst case: "\e[1;3;4;9;38;2;255;128;128;48;2;128;128;255mA\e[0m"
    # bold, italic, underline, crossed_out, RGB forgound, RGB background
    MAX_CHAR_PER_CELL = 50

    class << self
      def page_content(content, **options)
        if content_exceeds_screen_height?(content)
          page(**options) do |io|
            io.puts content
          end
        else
          $stdout.puts content
        end
      end

      def page(retain_content: false)
        if should_page? && pager = setup_pager(retain_content: retain_content)
          begin
            pid = pager.pid
            yield pager
          ensure
            pager.close
          end
        else
          yield $stdout
        end
      # When user presses Ctrl-C, IRB would raise `IRB::Abort`
      # But since Pager is implemented by running paging commands like `less` in another process with `IO.popen`,
      # the `IRB::Abort` exception only interrupts IRB's execution but doesn't affect the pager
      # So to properly terminate the pager with Ctrl-C, we need to catch `IRB::Abort` and kill the pager process
      rescue IRB::Abort
        begin
          begin
            Process.kill("TERM", pid) if pid
          rescue Errno::EINVAL
            # SIGTERM not supported (windows)
            Process.kill("KILL", pid)
          end
        rescue Errno::ESRCH
          # Pager process already terminated
        end
        nil
      rescue Errno::EPIPE
      end

      def should_page?
        IRB.conf[:USE_PAGER] && STDIN.tty? && (ENV.key?("TERM") && ENV["TERM"] != "dumb")
      end

      private

      def content_exceeds_screen_height?(content)
        screen_height, screen_width = begin
          Reline.get_screen_size
        rescue Errno::EINVAL
          [24, 80]
        end

        pageable_height = screen_height - 3 # leave some space for previous and the current prompt

        # If the content has more lines than the pageable height
        content.lines.count > pageable_height ||
        # Or if the content is a few long lines
        content.size > pageable_height * screen_width * MAX_CHAR_PER_CELL ||
        pageable_height * screen_width < Reline::Unicode.calculate_width(content, true)
      end

      def setup_pager(retain_content:)
        require 'shellwords'

        PAGE_COMMANDS.each do |pager_cmd|
          cmd = Shellwords.split(pager_cmd)
          next if cmd.empty?

          if cmd.first == 'less'
            cmd << '-R' unless cmd.include?('-R')
            cmd << '-X' if retain_content && !cmd.include?('-X')
          end

          begin
            io = IO.popen(cmd, 'w')
          rescue
            next
          end

          if $? && $?.pid == io.pid && $?.exited? # pager didn't work
            next
          end

          return io
        end

        nil
      end
    end

    class PagingIO
      attr_reader :string
      def initialize(width, height, &block)
        @lines = []
        @width = width
        @height = height
        @buffer = +''
        @block = block
        @col = 0
        @string = +''
        @multipage = false
      end

      def puts(text = '')
        write(text)
        write("\n") unless text.end_with?("\n")
      end

      def write(text)
        @string << text
        return if @multipage

        overflow_size = @width * @height * MAX_CHAR_PER_CELL
        if text.size >= overflow_size
          text = text[0, overflow_size]
          overflow = true
        end

        @buffer << text
        @col += Reline::Unicode.calculate_width(text)
        if text.include?("\n") || @col >= @width
          @buffer.lines.each do |line|
            wrapped_lines = Reline::Unicode.split_by_width(line.chomp, @width).first.compact
            wrapped_lines.pop if wrapped_lines.last == ''
            @lines.concat(wrapped_lines)
            if @lines.empty?
              @lines << "\n"
            elsif line.end_with?("\n")
              @lines[-1] += "\n"
            end
          end
          @buffer.clear
          @buffer << @lines.pop unless @lines.last.end_with?("\n")
          @col = Reline::Unicode.calculate_width(@buffer)
        end
        if overflow || @lines.size >= @height
          @block.call(@lines)
          @multipage = true
        end
      end

      def multipage?
        @multipage
      end

      alias print write
      alias << write
    end
  end
end
