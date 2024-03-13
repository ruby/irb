# frozen_string_literal: true

require_relative "command"
require_relative "command/exit"
require_relative "command/force_exit"
require_relative "command/chws"
require_relative "command/pushws"
require_relative "command/subirb"
require_relative "command/load"
require_relative "command/debug"
require_relative "command/edit"
require_relative "command/break"
require_relative "command/catch"
require_relative "command/next"
require_relative "command/delete"
require_relative "command/step"
require_relative "command/continue"
require_relative "command/finish"
require_relative "command/backtrace"
require_relative "command/info"
require_relative "command/help"
require_relative "command/show_doc"
require_relative "command/irb_info"
require_relative "command/ls"
require_relative "command/measure"
require_relative "command/show_source"
require_relative "command/whereami"
require_relative "command/history"

module IRB
  ExtendCommand = Command

  # Installs the default irb extensions command bundle.
  module ExtendCommandBundle
    EXCB = ExtendCommandBundle # :nodoc:

    # See #install_alias_method.
    NO_OVERRIDE = 0
    # See #install_alias_method.
    OVERRIDE_PRIVATE_ONLY = 0x01
    # See #install_alias_method.
    OVERRIDE_ALL = 0x02

    # Displays current configuration.
    #
    # Modifying the configuration is achieved by sending a message to IRB.conf.
    def irb_context
      IRB.CurrentContext
    end

    @ALIASES = [
      [:context, :irb_context, NO_OVERRIDE],
      [:conf, :irb_context, NO_OVERRIDE],
    ]

    Command._register_with_aliases(:irb_exit, Command::Exit,
      [:exit, OVERRIDE_PRIVATE_ONLY],
      [:quit, OVERRIDE_PRIVATE_ONLY],
      [:irb_quit, OVERRIDE_PRIVATE_ONLY]
    )

    Command._register_with_aliases(:irb_exit!, Command::ForceExit,
      [:exit!, OVERRIDE_PRIVATE_ONLY]
    )

    Command._register_with_aliases(:irb_current_working_workspace, Command::CurrentWorkingWorkspace,
      [:cwws, NO_OVERRIDE],
      [:pwws, NO_OVERRIDE],
      [:irb_print_working_workspace, OVERRIDE_ALL],
      [:irb_cwws, OVERRIDE_ALL],
      [:irb_pwws, OVERRIDE_ALL],
      [:irb_current_working_binding, OVERRIDE_ALL],
      [:irb_print_working_binding, OVERRIDE_ALL],
      [:irb_cwb, OVERRIDE_ALL],
      [:irb_pwb, OVERRIDE_ALL],
    )

    Command._register_with_aliases(:irb_change_workspace, Command::ChangeWorkspace,
      [:chws, NO_OVERRIDE],
      [:cws, NO_OVERRIDE],
      [:irb_chws, OVERRIDE_ALL],
      [:irb_cws, OVERRIDE_ALL],
      [:irb_change_binding, OVERRIDE_ALL],
      [:irb_cb, OVERRIDE_ALL],
      [:cb, NO_OVERRIDE],
    )

    Command._register_with_aliases(:irb_workspaces, Command::Workspaces,
      [:workspaces, NO_OVERRIDE],
      [:irb_bindings, OVERRIDE_ALL],
      [:bindings, NO_OVERRIDE],
    )

    Command._register_with_aliases(:irb_push_workspace, Command::PushWorkspace,
      [:pushws, NO_OVERRIDE],
      [:irb_pushws, OVERRIDE_ALL],
      [:irb_push_binding, OVERRIDE_ALL],
      [:irb_pushb, OVERRIDE_ALL],
      [:pushb, NO_OVERRIDE],
    )

    Command._register_with_aliases(:irb_pop_workspace, Command::PopWorkspace,
      [:popws, NO_OVERRIDE],
      [:irb_popws, OVERRIDE_ALL],
      [:irb_pop_binding, OVERRIDE_ALL],
      [:irb_popb, OVERRIDE_ALL],
      [:popb, NO_OVERRIDE],
    )

    Command._register_with_aliases(:irb_load, Command::Load)
    Command._register_with_aliases(:irb_require, Command::Require)
    Command._register_with_aliases(:irb_source, Command::Source,
      [:source, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb, Command::IrbCommand)
    Command._register_with_aliases(:irb_jobs, Command::Jobs,
      [:jobs, NO_OVERRIDE]
    )
    Command._register_with_aliases(:irb_fg, Command::Foreground,
      [:fg, NO_OVERRIDE]
    )
    Command._register_with_aliases(:irb_kill, Command::Kill,
      [:kill, OVERRIDE_PRIVATE_ONLY]
    )

    Command._register_with_aliases(:irb_debug, Command::Debug,
      [:debug, NO_OVERRIDE]
    )
    Command._register_with_aliases(:irb_edit, Command::Edit,
      [:edit, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_break, Command::Break)
    Command._register_with_aliases(:irb_catch, Command::Catch)
    Command._register_with_aliases(:irb_next, Command::Next)
    Command._register_with_aliases(:irb_delete, Command::Delete,
      [:delete, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_step, Command::Step,
      [:step, NO_OVERRIDE]
    )
    Command._register_with_aliases(:irb_continue, Command::Continue,
      [:continue, NO_OVERRIDE]
    )
    Command._register_with_aliases(:irb_finish, Command::Finish,
      [:finish, NO_OVERRIDE]
    )
    Command._register_with_aliases(:irb_backtrace, Command::Backtrace,
      [:backtrace, NO_OVERRIDE],
      [:bt, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_debug_info, Command::Info,
      [:info, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_help, Command::Help,
      [:help, NO_OVERRIDE],
      [:show_cmds, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_show_doc, Command::ShowDoc,
      [:show_doc, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_info, Command::IrbInfo)

    Command._register_with_aliases(:irb_ls, Command::Ls,
      [:ls, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_measure, Command::Measure,
      [:measure, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_show_source, Command::ShowSource,
      [:show_source, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_whereami, Command::Whereami,
      [:whereami, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_history, Command::History,
      [:history, NO_OVERRIDE],
      [:hist, NO_OVERRIDE]
    )

    def self.all_commands_info
      user_aliases = IRB.CurrentContext.command_aliases.each_with_object({}) do |(alias_name, target), result|
        result[target] ||= []
        result[target] << alias_name
      end

      Command.commands.map do |command_name, (command_class, aliases)|
        aliases = aliases.map { |a| a.first }

        if additional_aliases = user_aliases[command_name]
          aliases += additional_aliases
        end

        display_name = aliases.shift || command_name
        {
          display_name: display_name,
          description: command_class.description,
          category: command_class.category
        }
      end
    end

    # Convert a command name to its implementation class if such command exists
    def self.load_command(command)
      command = command.to_sym
      Command.commands.each do |command_name, (command_class, aliases)|
        if command_name == command || aliases.any? { |alias_name, _| alias_name == command }
          return command_class
        end
      end
      nil
    end

    # Installs the default irb commands.
    def self.define_command_as_methods
      Command.commands.each do |command_name, (command_class, aliases)|
        line = __LINE__; eval %[
          def #{command_name}(*opts, **kwargs, &b)
            #{command_class.name}.execute(irb_context, *opts, **kwargs, &b)
          end
        ], nil, __FILE__, line

        aliases.each do |alias_name, override|
          @ALIASES.push [alias_name, command_name, override]
        end
      end
    end

    # Installs alias methods for the default irb commands, see
    # ::define_command_as_methods.
    def install_alias_method(to, from, override = NO_OVERRIDE)
      to = to.id2name unless to.kind_of?(String)
      from = from.id2name unless from.kind_of?(String)

      if override == OVERRIDE_ALL or
          (override == OVERRIDE_PRIVATE_ONLY) && !respond_to?(to) or
          (override == NO_OVERRIDE) &&  !respond_to?(to, true)
        target = self
        (class << self; self; end).instance_eval{
          if target.respond_to?(to, true) &&
            !target.respond_to?(EXCB.irb_original_method_name(to), true)
            alias_method(EXCB.irb_original_method_name(to), to)
          end
          alias_method to, from
        }
      else
        Kernel.warn "irb: warn: can't alias #{to} from #{from}.\n"
      end
    end

    def self.irb_original_method_name(method_name) # :nodoc:
      "irb_" + method_name + "_org"
    end

    # Installs alias methods for the default irb commands on the given object
    # using #install_alias_method.
    def self.extend_object(obj)
      unless (class << obj; ancestors; end).include?(EXCB)
        super
        for ali, com, flg in @ALIASES
          obj.install_alias_method(ali, com, flg)
        end
      end
    end

    define_command_as_methods

    # Both @EXTEND_COMMANDS and def_extend_command could be used as an unofficial API
    # to add new commands to IRB. We should keep them for compatibility.
    # TODO: Remove these in version 2.0
    @EXTEND_COMMANDS = []

    def self.def_extend_command(command_name, command_class_symbol, require_path = nil, aliases = [])
      warn "IRB::ExtendCommandBundle.def_extend_command is deprecated and will be removed in the future. Use IRB::Command.register instead."
      require require_path if require_path
      Command._register_with_aliases(command_name, ExtendCommand.const_get(command_class_symbol), *aliases)
    end
  end
end
