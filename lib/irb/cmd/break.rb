# frozen_string_literal: true

require_relative "debug"

module IRB
  # :stopdoc:

  module ExtendCommand
    class Break < Debug
      def execute(*args)
        super(['break', *args].join(' '))
      end
    end
  end

  # :startdoc:
end
