# frozen_string_literal: true

require_relative "debug"

module IRB
  # :stopdoc:

  module ExtendCommand
    class Finish < Debug
      def execute(*args)
        super(['finish', *args].join(' '))
      end
    end
  end

  # :startdoc:
end
