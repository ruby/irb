# frozen_string_literal: false
require_relative "helper"

module TestIRB
  class OptionTest < TestCase
    def test_end_of_option
      bug4117 = '[ruby-core:33574]'
      bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
      libdir = File.expand_path("../../lib", __dir__)
      status = assert_in_out_err(bundle_exec + %W[-W0 -I#{libdir} -rirb -e IRB.start(__FILE__) -- -f --], "", //, [], bug4117)
      assert(status.success?, bug4117)
    end
  end
end
