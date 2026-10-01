require_relative "helper_method/base"
require "prism"

module IRB
  module HelperMethod
    @helper_methods = {}

    class << self
      attr_reader :helper_methods

      def register(name, helper_class)
        @helper_methods[name] = helper_class
        Container.define_singleton_method name do |*args, **opts, &block|
          helper_class.instance.execute(*args, **opts, &block)
        end
      end

      def all_helper_methods_info
        @helper_methods.map do |name, helper_class|
          { display_name: name, description: helper_class.description }
        end
      end

      # Injects helper method calls with the corresponding container method calls.
      # For example, `tap { p conf.ap_name }` will be transformed to `tap { p ::IRB::HelperMethod::Container.conf.ap_name }`.
      def inject_helper_methods(code, local_variables: [])
        parse_result = Prism.parse(code, scopes: [local_variables])
        return code unless parse_result.success?

        locations = extract_helper_method_locations(parse_result.value)
        return code if locations.empty?

        injected = +''
        offset = 0
        locations.each do |loc|
          injected << code.byteslice(offset...loc.start_offset)
          # Avoid `{x:conf}` being transformed to `{x:::IRB::HelperMethod::Container.conf}` which is a syntax error
          injected << ' ' if injected.end_with?(':')
          injected << "::IRB::HelperMethod::Container.#{loc.slice}"
          offset = loc.end_offset
        end
        injected << code.byteslice(offset..)
        injected
      end

      def completions(preposing, target, local_variables:)
        helper_method_names = @helper_methods.keys.map(&:to_s)
        candidates = helper_method_names.select {|name| name.start_with?(target) }
        return [] if candidates.empty?

        target_message = nil
        end_offset = preposing.bytesize + target.bytesize
        visitor = MethodCallVisitor.new do |call_node|
          target_message = call_node.message if call_node.message_loc.end_offset == end_offset
        end
        Prism.parse(preposing + target, scopes: [local_variables]).value.accept(visitor)
        return [] unless target_message

        candidates
      end

      def extract_helper_method_locations(node)
        helper_method_names = @helper_methods.keys.map(&:to_s)

        # Legacy helper methods defined in ExtendCommandBundle should also be considered as helper methods
        helper_method_names += IRB::ExtendCommandBundle.instance_methods.map(&:to_s)

        helper_method_locations = []
        visitor = MethodCallVisitor.new do |call_node|
          if helper_method_names.include?(call_node.message)
            helper_method_locations << call_node.message_loc
          end
        end
        visitor.visit(node)
        helper_method_locations.sort_by(&:start_offset)
      end
    end

    # Traverse and finds CallNode without receiver which may be helper method calls.
    class MethodCallVisitor < Prism::Visitor # :nodoc:
      def initialize(&block)
        @callback = block
      end

      def visit_call_node(node)
        super
        @callback.call node if node.receiver.nil?
      end

      def visit_implicit_node(node)
        # We can't modify `{ conf: }` to `{ ::IRB::HelperMethod::Container.conf: }`
        # so it can't be a helper method call
      end
    end

    Container = Object.new

    # Enable legacy helper method registration for backward compatibility
    require_relative "default_commands"
    Container.extend IRB::ExtendCommandBundle

    # Default helper_methods
    require_relative "helper_method/conf"
    register(:conf, HelperMethod::Conf)
  end
end
