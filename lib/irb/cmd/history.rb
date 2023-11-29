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
          header_length = header.size

          lines = input.split("\n")
          first_line = header + lines[0]

          truncated_input = lines[1..1]
          truncated_input << "..." if lines.size > 2

          truncated_input = truncated_input.map do |line|
            " " * header_length + line
          end

          output.puts first_line, *truncated_input
        end

        Pager.page_content(output.string)
      end
    end
  end

  # :startdoc:
end
