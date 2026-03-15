# frozen_string_literal: true

module IRB
  # :stopdoc:

  module Command
    class Reload < Base
      category "IRB"
      description "Reload files that were loaded via require in IRB session."

      def execute(_arg)
        unless reloadable_require_available?
          warn "The reload command requires IRB.conf[:RELOADABLE_REQUIRE] = true and Ruby::Box (Ruby 4.0+) with RUBY_BOX=1 environment variable."
          return
        end

        files = IRB.conf[:__RELOADABLE_FILES__]
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
        $LOADED_FEATURES.delete(path)
        load path
        $LOADED_FEATURES << path
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
