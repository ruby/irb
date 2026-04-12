# frozen_string_literal: true

module IRB
  # :stopdoc:

  module Command
    class BoxReload < Base
      category "IRB"
      description "[Experimental] Reload files that were loaded via require in IRB session (requires Ruby::Box)."

      help_message <<~HELP
        Usage: box_reload

        Reloads all Ruby files that were loaded via `require` or `require_relative`
        during the current IRB session. This allows you to pick up changes made to
        source files without restarting IRB.

        Setup:
          1. Start Ruby with RUBY_BOX=1 environment variable
          2. Set IRB.conf[:RELOADABLE_REQUIRE] = true in your .irbrc

        Example:
          # In .irbrc:
          IRB.conf[:RELOADABLE_REQUIRE] = true

          # In IRB session:
          require 'my_lib'  # loaded and tracked
          # ... edit my_lib.rb ...
          box_reload         # reloads the file

        Note: This feature is experimental and requires Ruby::Box (Ruby 4.0+).
        Native extensions (.so/.bundle) cannot be reloaded.
      HELP

      def execute(_arg)
        unless reloadable_require_available?
          warn "box_reload requires IRB.conf[:RELOADABLE_REQUIRE] = true and Ruby::Box (Ruby 4.0+) with RUBY_BOX=1 environment variable."
          return
        end

        ReloadableRequire.collect_autoloaded_files
        files = ReloadableRequire.reloadable_files
        if files.empty?
          puts "No files to reload. Use require to load files first."
          return
        end

        files.each { |path| reload_file(path) }
      end

      private

      def reloadable_require_available?
        IRB.conf[:RELOADABLE_REQUIRE] && defined?(Ruby::Box) && Ruby::Box.enabled?
      end

      def reload_file(path)
        load path
        puts "Reloaded: #{path}"
      rescue LoadError => e
        warn "Failed to reload #{path}: #{e.message}"
      rescue SyntaxError => e
        warn "Syntax error in #{path}: #{e.message}"
      end
    end
  end

  # :startdoc:
end
