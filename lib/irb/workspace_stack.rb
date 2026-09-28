# frozen_string_literal: true

module IRB
  # The stack of workspaces of an IRB session.
  #
  # The bottom workspace is the home workspace, which is fixed at creation. The
  # top workspace is the current one, where input is evaluated. The stack is
  # never empty.
  #
  # Every workspace that becomes current goes through this class, so this is the
  # only place that loads helper methods into a workspace's main object.
  class WorkspaceStack
    include Enumerable

    def initialize(home)
      @stack = []
      push(home)
    end

    # The workspace the session started with.
    def home
      @stack.first
    end

    # The workspace where input is evaluated.
    def current
      @stack.last
    end

    def size
      @stack.size
    end

    def each(&block)
      @stack.each(&block)
    end

    def push(workspace)
      workspace.load_helper_methods_to_main
      @stack.push(workspace)
      workspace
    end

    # Removes and returns the current workspace. The home workspace is never
    # removed, +nil+ is returned instead.
    def pop
      @stack.pop if @stack.size > 1
    end

    # Swaps the two topmost workspaces. Does nothing if there's only one.
    def swap
      return if @stack.size < 2

      previous_workspace, current_workspace = @stack.pop(2)
      @stack.push(current_workspace, previous_workspace)
    end

    # Replaces the current workspace with +workspace+.
    def replace(workspace)
      workspace.load_helper_methods_to_main
      @stack[-1] = workspace
    end

    # Makes +workspace+ current while the block runs.
    def with(workspace)
      previous_workspace = current
      replace(workspace)
      yield
    ensure
      @stack[-1] = previous_workspace
    end

    def inspect # :nodoc:
      "#<#{self.class} #{@stack.map(&:main).inspect}>"
    end
  end
end
