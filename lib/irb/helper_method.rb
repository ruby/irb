require_relative "helper_method/base"

module IRB
  module HelperMethod
    @helper_methods = {}

    class << self
      attr_reader :helper_methods

      def register(name, helper_class)
        @helper_methods[name] = helper_class
      end

      def all_helper_methods_info
        @helper_methods.map do |name, helper_class|
          { display_name: name, description: helper_class.description }
        end
      end
    end

    # Default helper_methods
    require_relative "helper_method/conf"
    require_relative "helper_method/context"
    require_relative "helper_method/irb_context"
    register(:conf, HelperMethod::Conf)
    register(:context, HelperMethod::Context)
    register(:irb_context, HelperMethod::IrbContext)
  end
end
