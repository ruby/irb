# frozen_string_literal: true

module IRB
  module Command
    class CD < Base
      category "Workspace"
      description "Move into the given object or leave the current context."

      help_message(<<~HELP)
        Usage: cd ([target]|..)

        When given an object, cd will move into that object, making it the current context.
        When given "..", cd will leave the current context, moving back to the previous context.
        When given no arguments, cd will move back to the top-level (main object) context.

        Examples:

          cd Foo
          cd Foo.new
          cd @ivar
          cd ..
          cd
      HELP

      def execute(arg)
        case arg
        when ".."
          irb_context.pop_workspace
        when ""
          # TODO: decide what workspace commands should be kept, and underlying APIs should look like,
          # and perhaps add a new API to clear the workspace stack.
          prev_workspace = irb_context.pop_workspace
          while prev_workspace
            prev_workspace = irb_context.pop_workspace
          end
        else
          begin
            obj = eval(arg, irb_context.workspace.binding)
            irb_context.push_workspace(obj)
          rescue StandardError => e
            warn "Error: #{e}"
          end
        end
      end
    end
  end
end
