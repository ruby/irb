# frozen_string_literal: true

require "stringio"
require_relative "nop"
require_relative "../pager"

module IRB
  # :stopdoc:

  module ExtendCommand
    class History < Nop
      category "IRB"
      description "Shows the input history. `-g [query]` or `-G [query]` allows you to filter the output."

      def self.transform_args(args)
        if match = args&.match(/\A(?<args>.+\s|)(-g|-G)\s+(?<grep>[^\s]+)\s*\n\z/)
          args = match[:args]
          "#{args}#{',' unless args.chomp.empty?} grep: /#{match[:grep]}/"
        else
          args
        end
      end

      def execute(*arg, grep: nil)
        formatted_inputs = irb_context.io.class::HISTORY.each_with_index.reverse_each.map do |input, index|
          header = "#{index}: "

          first_line, *other_lines = input.split("\n") || [""]
          first_line.prepend header

          truncated_lines = other_lines.slice!(1..) # Show 1 additional line (2 total)
          other_lines << "..." if truncated_lines&.any?

          other_lines.map! do |line|
            " " * header.length + line
          end

          StringIO.new.tap { |io| io.puts(first_line, *other_lines) }.string
        end

        formatted_inputs = formatted_inputs.grep(grep) if grep

        Pager.page_content(formatted_inputs.join)
      end
    end
  end

  # :startdoc:
end
