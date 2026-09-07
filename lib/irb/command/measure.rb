module IRB
  # :stopdoc:

  module Command
    class Measure < Base
      include RubyArgsExtractor

      category "Misc"
      description "`measure` enables the mode to measure processing time. `measure :off` disables it."

      def initialize(*args)
        super(*args)
      end

      def execute(arg)
        if arg&.match?(/^do$|^do[^\w]|^\{/)
          warn 'Configure IRB.conf[:MEASURE_PROC] to add custom measure methods.'
          return
        end
        args, kwargs = ruby_args(arg)
        execute_internal(*args, **kwargs)
      end

      def execute_internal(type = nil, arg = nil)
        # Please check IRB.init_config in lib/irb/init.rb that sets
        # IRB.conf[:MEASURE_PROC] to register default "measure" methods,
        # "measure :time" (abbreviated as "measure") and "measure :stackprof".

        case type
        when :off
          IRB.unset_measure_callback(arg)
        when :list
          IRB.conf[:MEASURE_CALLBACKS].each do |type_name, _, arg_val|
            puts "- #{type_name}" + (arg_val ? "(#{arg_val.inspect})" : '')
          end
        when :on
          added = IRB.set_measure_callback(arg)
          display_added_message(added[0]) if added
        else
          added = IRB.set_measure_callback(type, arg)
          display_added_message(added[0]) if added
        end
        nil
      end

      private

      def display_added_message(added)
        puts "#{added} is added."
      end
    end
  end

  # :startdoc:
end
