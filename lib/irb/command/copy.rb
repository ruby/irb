# frozen_string_literal: true

require 'mkmf'

module IRB
  module Command
    class Copy < Base
      category "TODO"
      description "TODO"

      help_message(<<~HELP)
        Usage: copy (input)
      HELP

      def execute(arg)
        output = irb_context.workspace.binding.eval(arg)

        if clipboard_available?
          copy_to_clipboard(output)
          puts "Copied to system clipboard"
        else
          temp_file = write_to_tempfile(output)
          puts "Wrote: #{temp_file}"
        end
      rescue StandardError => e
        warn "Error: #{e}"
      end

      private

      def copy_to_clipboard(text)
        IO.popen(clipboard, 'w') do |io|
          io.write(text)
        end

        raise "IOError" unless $? == 0
      end

      def write_to_tempfile(text)
        file = Tempfile.new
        file.write(text)
        file.close
        file.path
      end

      def clipboard
        case RbConfig::CONFIG['host_os']
        when /darwin/
          # This is the most reliable method, but we could probably also offload this
          # to the shell to avoid MkMf logs
          MakeMakefile.find_executable('pbcopy')
        when /linux/
          MakeMakefile.find_executable('xclip').tap do |path|
            path << '-selection clipboard'
          end
        when /mswin|mingw/
          'clip' # => todo verify this works
        else
          nil
        end
      end

      def clipboard_available?
        !!clipboard
      end
    end
  end
end
