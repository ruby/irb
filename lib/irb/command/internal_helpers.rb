# frozen_string_literal: true

require 'prism'

module IRB
  module Command
    # Internal use only, for default command's backward compatibility.
    module RubyArgsExtractor # :nodoc:
      def unwrap_string_literal(str)
        return if str.empty?

        result = Prism.parse(str)
        body = result.value.statements.body
        if result.success? && body.size == 1 && body.first.is_a?(Prism::StringNode)
          body.first.unescaped
        else
          str
        end
      end

      def ruby_args(arg)
        # Use throw and catch to handle arg that includes `;`
        # For example: "1, kw: (2; 3); 4" will be parsed to [[1], { kw: 3 }]
        catch(:EXTRACT_RUBY_ARGS) do
          @irb_context.workspace.binding.eval "::IRB::Command.extract_ruby_args #{arg}"
        end || [[], {}]
      end
    end
  end
end
