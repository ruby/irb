# frozen_string_literal: true

if !defined?(Ruby::Box) || !Ruby::Box.enabled?
  raise "ReloadableRequire requires Ruby::Box to be enabled"
end

require 'set'

module IRB
  # Provides reload-aware require functionality for IRB.
  #
  # Limitations:
  # - Native extensions cannot be reloaded (load doesn't support them)
  # - Files loaded via box.require are not tracked
  # - Constant redefinition warnings will appear on reload (uses load internally)
  # - Context mode 5 (running IRB inside a Ruby::Box) is not supported
  #
  # This feature requires Ruby::Box (Ruby 4.0+).

  unless Ruby::Box.method_defined?(:__irb_original_require__)
    Ruby::Box.class_eval do
      alias_method :__irb_original_require__, :require
      alias_method :__irb_original_require_relative__, :require_relative
    end
  end

  Ruby::Box.class_eval do
    def __irb_reloadable_require__(feature)
      unless IRB::ReloadableRequire.autoload_files.include?(feature)
        return __irb_original_require__(feature)
      end

      IRB::ReloadableRequire.autoload_files.delete(feature)
      IRB::ReloadableRequire.track_and_load_files($LOADED_FEATURES, Ruby::Box.main) { __irb_original_require__(feature) }
    end

    def __irb_reloadable_require_relative__(feature)
      __irb_original_require_relative__(feature)
    end
  end

  module ReloadableRequire
    @reloadable_files = Set.new
    @autoload_files = Set.new

    class << self
      attr_reader :reloadable_files, :autoload_files

      def extended(base)
        apply_autoload_hook
      end

      def apply_autoload_hook
        Ruby::Box.class_eval do
          alias_method :require, :__irb_reloadable_require__
          alias_method :require_relative, :__irb_reloadable_require_relative__
        end
      end

      def track_and_load_files(source, current_box)
        before = source.dup
        result = yield
        new_files = source - before

        return result if new_files.empty?

        ruby_files, native_extensions = new_files.partition { |path| path.end_with?('.rb') }

        native_extensions.each { |path| current_box.require(path) }

        @reloadable_files.merge(ruby_files)

        main_loaded_features = current_box.eval('$LOADED_FEATURES')
        main_loaded_features.concat(ruby_files - main_loaded_features)
        ruby_files.each { |path| current_box.load(path) }

        result
      end
    end

    private

    def reloadable_require_internal(feature, caller_box)
      box = Ruby::Box.new
      box.eval("$LOAD_PATH.concat(#{caller_box.eval('$LOAD_PATH')})")
      box.eval("$LOADED_FEATURES.concat(#{caller_box.eval('$LOADED_FEATURES')})")

      ReloadableRequire.track_and_load_files(box.eval('$LOADED_FEATURES'), caller_box) { box.__irb_original_require__(feature) }
    end

    def require(feature)
      caller_loc = caller_locations(1, 1).first
      current_box = Ruby::Box.main
      return current_box.__irb_original_require__(feature) unless caller_loc.path.end_with?("(irb)")

      resolved = current_box.eval("$LOAD_PATH.resolve_feature_path(#{feature.dump})")
      return current_box.__irb_original_require__(feature) unless resolved&.first == :rb

      reloadable_require_internal(feature, current_box)
    end

    def require_relative(feature)
      caller_loc = caller_locations(1, 1).first
      current_box = Ruby::Box.main

      unless caller_loc.path.end_with?("(irb)")
        file_path = caller_loc.absolute_path || caller_loc.path
        return current_box.eval("eval('Kernel.require_relative(#{feature.dump})', nil, #{file_path.dump}, #{caller_loc.lineno})")
      end

      reloadable_require_internal(File.expand_path(feature, Dir.pwd), current_box)
    end

    def autoload(const, feature)
      ReloadableRequire.autoload_files << feature
      Ruby::Box.main.eval("Kernel.autoload(:#{const}, #{feature.dump})")
    end
  end
end
