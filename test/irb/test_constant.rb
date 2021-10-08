# frozen_string_literal: false
require 'test/unit'

module TestIRB
  class TestConstant < Test::Unit::TestCase
    def test_version
      bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
      assert_in_out_err(bundle_exec + %w[-rirb -W0 -e IRB.start(__FILE__) -- -f --], <<-IRB, /true/, [])
        RUBY_VERSION = nil
        RUBY_VERSION.nil?
      IRB
    end
  end
end
