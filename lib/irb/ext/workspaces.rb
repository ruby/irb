# frozen_string_literal: true
#
#   push-ws.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

module IRB # :nodoc:
  class Context
    # Creates a new workspace with the given object or binding, and appends it
    # onto the current #workspaces stack.
    #
    # See IRB::Context#change_workspace and IRB::WorkSpace.new for more
    # information.
    def push_workspace(*_main)
      if _main.empty?
        if @workspace_stack.size == 1
          print "No other workspace\n"
        else
          # swap the top two workspaces
          previous_workspace, current_workspace = @workspace_stack.pop
          @workspace_stack.push current_workspace, previous_workspace
        end
      else
        @workspace_stack.push WorkSpace.new(workspace.binding, _main[0])
        if !(class<<main;ancestors;end).include?(ExtendCommandBundle)
          main.extend ExtendCommandBundle
        end
      end

      nil
    end

    # Removes the last element from the current #workspaces stack and returns
    # it, or +nil+ if the current workspace stack is empty.
    #
    # Also, see #push_workspace.
    def pop_workspace
      if @workspace_stack.size == 1
        print "Can't pop the last workspace on the stack\n"
      else
        @workspace_stack.pop
      end

      nil
    end
  end
end
