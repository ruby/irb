# frozen_string_literal: true
#
#   change-ws.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

require_relative "../ext/workspaces"

module IRB
  # :stopdoc:

  module Command
    class Workspaces < Base
      category "Workspace"
      description "Show workspaces."

      def execute(_arg)
        irb_context.workspaces.collect{|ws| ws.main}
      end
    end

    class PushWorkspace < Workspaces
      category "Workspace"
      description "Push an object to the workspace stack."

      def execute(arg)
        if arg.empty?
          irb_context.push_workspace
        else
          obj = eval(arg, irb_context.workspace.binding)
          irb_context.push_workspace(obj)
        end
        super
      end
    end

    class PopWorkspace < Workspaces
      category "Workspace"
      description "Pop a workspace from the workspace stack."

      def execute(_arg)
        irb_context.pop_workspace
        super
      end
    end
  end

  # :startdoc:
end
