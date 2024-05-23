module IRB
  # :stopdoc:

  module Command
    class Measure < Base
      category "Misc"
      description "`measure` enables the mode to measure processing time. `measure off` disables it."

      def execute(arg)
        if arg&.match?(/^do$|^do[^\w]|^\{/)
          warn 'Configure IRB.conf[:MEASURE_PROC] to add custom measure methods.'
          return
        end

        if arg.empty?
          execute_internal(nil, nil)
        elsif arg.start_with? ':'
          # Legacy style `measure :stackprof`, `measure :off, :time`
          type, arg_val = arg.split(/,\s*/, 2).map { |v| v.sub(/\A:/, '') }
          warn "`measure #{arg}` is deprecated. Please use `measure #{[type, arg_val].compact.join(' ')}` instead."
          execute_internal(type.to_sym, arg_val)
        else
          type, arg_val = arg.split(/\s+/, 2)
          execute_internal(type.to_sym, arg_val)
        end
      end

      def execute_internal(type, arg)
        # Please check IRB.init_config in lib/irb/init.rb that sets
        # IRB.conf[:MEASURE_PROC] to register default "measure" methods,
        # "measure time" (abbreviated as "measure") and "measure stackprof".

        case type
        when :off
          IRB.unset_measure_callback(arg&.to_sym)
        when :list
          IRB.conf[:MEASURE_CALLBACKS].each do |type_name, _, arg_val|
            puts "- #{type_name}" + (arg_val ? "(#{arg_val.inspect})" : '')
          end
        else
          type, arg = arg&.to_sym, nil if type == :on

          measure_methods = IRB.conf[:MEASURE_PROC].keys.map(&:downcase)
          if type && !measure_methods.include?(type)
            puts "Measure method `#{type}` not found."
            puts "Available measure methods: %w[#{measure_methods.join(' ')}]."
          else
            added = IRB.set_measure_callback(type&.to_sym, arg)
            puts "#{added[0]} is added." if added
          end
        end
        nil
      end
    end
  end

  # :startdoc:
end
