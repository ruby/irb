# frozen_string_literal: true
#
#   nop.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

module IRB
  module Command
    class CommandArgumentError < StandardError; end # :nodoc:

    class << self
      def extract_ruby_args(*args, **kwargs) # :nodoc:
        throw :EXTRACT_RUBY_ARGS, [args, kwargs]
      end
    end

    class Base
      class << self
        def category(category = nil)
          @category = category if category
          @category || "No category"
        end

        def description(description = nil)
          @description = description if description
          @description || "No description provided."
        end

        def help_message(help_message = nil)
          @help_message = help_message if help_message
          @help_message
        end

        def execute(irb_context, arg)
          new(irb_context).execute(arg)
        rescue CommandArgumentError => e
          puts e.message
        end

        # Returns formatted lines for display in the doc dialog popup.
        def doc_dialog_content(name, width)
          lines = []
          lines << Color.colorize(name, [:BOLD, :BLUE]) + Color.colorize(" (command)", [:CYAN])
          lines << ""
          lines.concat(wrap_lines(description, width))
          if help_message
            lines << ""
            lines.concat(wrap_lines(help_message, width))
          end
          lines
        end

        private

        def highlight(text)
          Color.colorize(text, [:BOLD, :BLUE])
        end

        def wrap_lines(text, width)
          text.lines.flat_map do |line|
            line = line.chomp
            next [''] if line.empty?
            next [line] if line.length <= width

            indent = line[/\A\s*/]
            words = line.strip.split(/\s+/)
            result = []
            current = indent.dup
            words.each do |word|
              if current == indent
                current << word
              elsif current.length + 1 + word.length <= width
                current << ' ' << word
              else
                result << current
                current = indent.dup + word
              end
            end
            result << current unless current == indent
            result
          end
        end
      end

      def initialize(irb_context)
        @irb_context = irb_context
      end

      attr_reader :irb_context

      def execute(arg)
        #nop
      end
    end

    Nop = Base # :nodoc:
  end
end
