# frozen_string_literal: true

require_relative "nop"

module IRB
  module ExtendCommand
    class ExitProgram < Nop
      category "Misc"
      description "End the current program, optionally with a status to give to `Kernel.exit`"

      def execute(arg = true)
        Kernel.exit(arg)
      end
    end
  end
end
