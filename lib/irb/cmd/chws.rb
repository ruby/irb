# frozen_string_literal: false
#
#   change-ws.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

require_relative "nop"
require_relative "../ext/change-ws"

module IRB
  # :stopdoc:

  module ExtendCommand

    class CurrentWorkingWorkspace < Nop
      category "IRB"
      description "Show the current workspace."

      def execute(*obj)
        irb_context.main
      end
    end

    class ChangeWorkspace < Nop
      category "IRB"
      description "Change the current workspace to an object."

      def execute(*obj)
        objs = obj.map { |o| irb_context.workspace.binding.eval(o)}
        irb_context.change_workspace(*objs)
        irb_context.main
      end
    end
  end

  # :startdoc:
end
