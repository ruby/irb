# frozen_string_literal: true

module IRB
  class Statement
    attr_reader :code, :is_assignment

    def initialize(code, is_assignment, command, arg, command_class)
      @code = code
      @is_assignment = is_assignment
      @command = command
      @arg = arg
      @command_class = command_class
    end

    def suppresses_echo?
      @code.match?(/;\s*\z/)
    end

    # First, let's pass debugging command's input to debugger
    # Secondly, we need to let debugger evaluate non-command input
    # Otherwise, the expression will be evaluated in the debugger's main session thread
    # This is the only way to run the user's program in the expected thread
    def should_be_handled_by_debugger?
      !@command_class || IRB::ExtendCommand::DebugCommand > @command_class
    end

    # Because IRB accepts symbol aliases, the code user inputs may not be evaluable Ruby code
    # This method returns code that's evaluable by Ruby
    def evaluable_code
      return @code unless @command_class

      # Hook command-specific transformation
      if @command_class.respond_to?(:transform_args)
        arg = @command_class.transform_args(@arg)
      else
        arg = @arg
      end

      [@command, arg].compact.join(' ')
    end
  end
end
