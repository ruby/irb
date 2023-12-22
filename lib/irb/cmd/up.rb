# frozen_string_literal: true

require_relative "debug"

module IRB
  # :stopdoc:

  module ExtendCommand
    class Up < DebugCommand
      def execute(*args)
        super(pre_cmds: ["up", *args].join(" "))
      end
    end
  end

  # :startdoc:
end
