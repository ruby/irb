# frozen_string_literal: false
#
#   nop.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

module IRB
  # :stopdoc:

  module ExtendCommand
    class CommandArgumentError < StandardError; end

    class Nop
      class << self
        def category(category = nil)
          @category = category if category
          @category
        end

        def description(description = nil)
          @description = description if description
          @description
        end

        private

        def string_literal?(args)
          sexp = Ripper.sexp(args)
          sexp && sexp.size == 2 && sexp.last&.first&.first == :string_literal
        end
      end

      def self.execute(irb_context, *opts, **kwargs, &block)
        command = new(irb_context)
        command.execute(*opts, **kwargs, &block)
      rescue CommandArgumentError => e
        puts e.message
      end

      def initialize(irb_context)
        @irb_context = irb_context
      end

      attr_reader :irb_context

      def execute(*opts)
        #nop
      end

      def transform_args(raw_args)
        if string_literal?(raw_args)
          evaluate(raw_args)
        else
          raw_args
        end
      end

      def execute_with_raw_args(raw_args)
        if raw_args.nil? || raw_args.empty?
          execute
        else
          raw_args = raw_args.strip

          args =
            if respond_to?(:transform_args)
              transform_args(raw_args)
            else
              evaluate(raw_args)
            end
          execute(args)
        end
      end

      private

      def string_literal?(args)
        sexp = Ripper.sexp(args)
        sexp && sexp.size == 2 && sexp.last&.first&.first == :string_literal
      end

      def evaluate(str)
        eval(str, @irb_context.workspace.binding)
      end
    end
  end

  # :startdoc:
end
