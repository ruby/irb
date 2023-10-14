# frozen_string_literal: true

require_relative "nop"

module IRB
  module ExtendCommand
    class ShowDoc < Nop
      class << self
        def transform_args(args)
          # Return a string literal as is for backward compatibility
          if args.empty? || string_literal?(args)
            args
          else # Otherwise, consider the input as a String for convenience
            args.strip.dump
          end
        end
      end

      category "Context"
      description "Enter the mode to look up RI documents."

      def execute(*names)
        rdoc_driver = irb_context.rdoc_driver

        if names.empty?
          rdoc_driver.interactive
        else
          names.each do |name|
            begin
              rdoc_driver.display_name(name.to_s)
            rescue RDoc::RI::Error
              puts $!.message
            end
          end
        end

        nil
      rescue LoadError, SystemExit
        warn "Can't display document because `rdoc` is not installed."
      end
    end
  end
end
