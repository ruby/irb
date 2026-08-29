# frozen_string_literal: true

module IRB
  # :stopdoc:

  module Command
    class Whereami < Base
      category "Context"
      description "Show the source code around binding.irb again. `-f` shows the full file."

      def execute(arg)
        code = irb_context.workspace.code_around_binding(
          show_full_file: arg.split.first == "-f"
        )

        if code
          puts code
        else
          puts "The current context doesn't have code."
        end
      end
    end
  end

  # :startdoc:
end
