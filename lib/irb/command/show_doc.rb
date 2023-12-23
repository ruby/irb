# frozen_string_literal: true

module IRB
  module Command
    class ShowDoc < Base
      category "Context"
      description "Enter the mode to look up RI documents."

      def execute(arg)
        # Accept string literal for backward compatibility
        name = unwrap_string_literal(arg)
        require 'rdoc/ri/driver'

        unless ShowDoc.const_defined?(:Ri)
          opts = RDoc::RI::Driver.process_args([])
          ShowDoc.const_set(:Ri, RDoc::RI::Driver.new(opts))
        end

        if name.nil?
          Ri.interactive
        else
          begin
            Ri.display_name(name)
          rescue RDoc::RI::Error
            puts $!.message
          end
        end

        nil
      rescue LoadError, SystemExit
        warn "Can't display document because `rdoc` is not installed."
      end
    end
  end
end
