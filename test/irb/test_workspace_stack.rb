# frozen_string_literal: false
require 'irb'

require_relative "helper"

module TestIRB
  class WorkspaceStackTest < TestCase
    def setup
      @home = IRB::WorkSpace.new(Object.new)
      @stack = IRB::WorkspaceStack.new(@home)
    end

    def test_home_is_current_on_creation
      assert_same(@home, @stack.home)
      assert_same(@home, @stack.current)
      assert_equal(1, @stack.size)
    end

    def test_push_and_pop
      workspace = IRB::WorkSpace.new(Object.new)
      @stack.push(workspace)
      assert_same(workspace, @stack.current)
      assert_same(@home, @stack.home)

      assert_same(workspace, @stack.pop)
      assert_same(@home, @stack.current)
    end

    def test_pop_never_removes_the_home_workspace
      assert_nil(@stack.pop)
      assert_same(@home, @stack.current)
    end

    def test_swap
      workspace = IRB::WorkSpace.new(Object.new)
      @stack.push(workspace)
      @stack.swap
      assert_equal([workspace, @home], @stack.to_a)
    end

    def test_replace_keeps_home_when_it_is_not_current
      pushed = IRB::WorkSpace.new(Object.new)
      replacement = IRB::WorkSpace.new(Object.new)
      @stack.push(pushed)
      @stack.replace(replacement)
      assert_equal([@home, replacement], @stack.to_a)
    end

    def test_with_restores_the_current_workspace
      workspace = IRB::WorkSpace.new(Object.new)
      @stack.with(workspace) do
        assert_same(workspace, @stack.current)
        raise "error"
      end
    rescue RuntimeError
      assert_same(@home, @stack.current)
    end

    def test_workspaces_get_helper_methods_when_they_become_current
      main = Object.new
      @stack.push(IRB::WorkSpace.new(main))
      assert_include(main.singleton_class.ancestors, IRB::ExtendCommandBundle)

      main = Object.new
      @stack.replace(IRB::WorkSpace.new(main))
      assert_include(main.singleton_class.ancestors, IRB::ExtendCommandBundle)
    end
  end
end
