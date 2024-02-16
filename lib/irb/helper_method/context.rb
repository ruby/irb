require_relative "conf"

module IRB
  module HelperMethod
    class Context < Conf
      description "Returns the current context."

      def execute
        IRB.CurrentContext
      end
    end
  end
end
