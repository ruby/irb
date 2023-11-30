# frozen_string_literal: true

require "stringio"
require_relative "nop"
require_relative "../pager"

module IRB
  # :stopdoc:

  module ExtendCommand
    class History < Nop
      category "IRB"
      description "Show the input history."

      def execute(*)
        output = StringIO.new
        irb_context.io.class::HISTORY.each_with_index.reverse_each do |input, index|
          header = "#{index}: "

          first_line, *other_lines = input.split("\n") || [""]
          first_line.prepend header

          truncated_lines = other_lines.slice!(1..) # Show 1 additional line (2 total)
          other_lines << "..." if truncated_lines&.any?

          other_lines.map! do |line|
            " " * header.length + line
          end

          output.puts first_line, *other_lines
        end

        Pager.page_content(output.string)
      end
    end
  end

  # :startdoc:
end
