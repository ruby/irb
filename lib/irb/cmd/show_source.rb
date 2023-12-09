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
        def set_options(options, parser)
          parser.on("-s", "show super method") do |v|
            options[:super_level] ||= 0
            options[:super_level] += 1
          end
        end

        def transform_args(args)
          # Return a string literal as is for backward compatibility
          if args.empty? || string_literal?(args)
            args
          else # Otherwise, consider the input as a String for convenience
            args.strip.dump
          end
        end
      end

      def execute(str = nil, super_level: nil)
        unless str.is_a?(String)
          puts "Error: Expected a string but got #{str.inspect}"
          return
        end

        super_level ||= 0
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
        file_content = IRB::Color.colorize_code(File.read(source.file))
        code = file_content.lines[(source.first_line - 1)...source.last_line].join
        content = <<~CONTENT

          #{bold("From")}: #{source.file}:#{source.first_line}

          #{code}
        CONTENT

        Pager.page_content(content)
      end

      def bold(str)
        Color.colorize(str, [:BOLD])
      end
    end
  end
end
