# frozen_string_literal: true

require_relative "nop"
require_relative "../source_finder"
require_relative "../pager"
require_relative "../color"

module IRB
  module ExtendCommand
    class ShowSource < Nop
      category "Context"
      description "Show the source code of a given method or constant."

      class << self
        def transform_args(args)
          # Return a string literal as is for backward compatibility
          if args.empty? || string_literal?(args)
            args
          else # Otherwise, consider the input as a String for convenience
            args.strip.dump
          end
        end
      end

      def execute(str = nil)
        unless str.is_a?(String)
          puts "Error: Expected a string but got #{str.inspect}"
          return
        end

        str, esses = str.split(" -")
        super_level = esses ? esses.count("s") : 0
        source = SourceFinder.new(@irb_context).find_source(str, super_level)

        if source
          show_source(source)
        elsif super_level > 0
          puts "Error: Couldn't locate a super definition for #{str}"
        else
          puts "Error: Couldn't locate a definition for #{str}"
        end
        nil
      end

      private

      def show_source(source)
        if source.content
          code = IRB::Color.colorize_code(source.content)
        elsif source.first_line && source.last_line
          file_content = IRB::Color.colorize_code(File.read(source.file))
          code = file_content.lines[(source.first_line - 1)...source.last_line].join
        elsif source.first_line
          code = 'Source not available'
        else
          content = "\n#{bold('Defined in binary file')}: #{source.file}\n\n"
        end
        content ||= <<~CONTENT

          #{bold("From")}: #{source.file}:#{source.first_line}

          #{code.chomp}

        CONTENT

        Pager.page_content(content)
      end

      def bold(str)
        Color.colorize(str, [:BOLD])
      end
    end
  end
end
