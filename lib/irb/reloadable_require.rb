# frozen_string_literal: true

if !defined?(Ruby::Box) || !Ruby::Box.enabled?
  raise "ReloadableRequire requires Ruby::Box to be enabled"
end

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

  class << self
    def track_and_load_files(source, current_box)
      before = source.dup
      result = yield
      new_files = source - before

      return result if new_files.empty?

      ruby_files, native_extensions = new_files.partition { |path| path.end_with?('.rb') }

      native_extensions.each { |path| current_box.require(path) }

      IRB.conf[:__RELOADABLE_FILES__].merge(ruby_files)

      main_loaded_features = current_box.eval('$LOADED_FEATURES')
      main_loaded_features.concat(ruby_files - main_loaded_features)
      ruby_files.each { |path| current_box.load(path) }

      result
    end
  end

  Ruby::Box.class_eval do
    alias_method :__irb_original_require__, :require
    alias_method :__irb_original_require_relative__, :require_relative

    def __irb_reloadable_require__(feature)
      unless IRB.conf[:__AUTOLOAD_FILES__].include?(feature)
        return __irb_original_require__(feature)
      end

      IRB.conf[:__AUTOLOAD_FILES__].delete(feature)
      IRB.track_and_load_files($LOADED_FEATURES, Ruby::Box.main) { __irb_original_require__(feature) }
    end

    def __irb_reloadable_require_relative__(feature)
      __irb_original_require_relative__(feature)
    end
  end

  module ReloadableRequire
    class << self
      def extended(base)
        apply_autoload_hook
      end

      def apply_autoload_hook
        Ruby::Box.class_eval do
          alias_method :require, :__irb_reloadable_require__
          alias_method :require_relative, :__irb_reloadable_require_relative__
        end
      end
    end

    private

    def reloadable_require_internal(absolute_path, caller_box)
      return false if caller_box.eval('$LOADED_FEATURES').include?(absolute_path)

      box = Ruby::Box.new
      load_path = caller_box.eval('$LOAD_PATH')
      # Copy $LOAD_PATH to the box so it can resolve dependencies.
      box.eval("$LOAD_PATH.concat(#{load_path})")

      IRB.track_and_load_files(box.eval('$LOADED_FEATURES'), caller_box) { box.__irb_original_require__(absolute_path) }
    end

    def require(feature)
      caller_loc = caller_locations(1, 1).first
      current_box = Ruby::Box.main
      resolved = current_box.eval("$LOAD_PATH.resolve_feature_path(#{feature.dump})")

      # Fallback for calls outside IRB prompt
      if caller_loc.path != "(irb)" || !resolved || resolved[0] != :rb
        return current_box.require(feature)
      end

      reloadable_require_internal(resolved[1], current_box)
    end

    def require_relative(feature)
      caller_loc = caller_locations(1, 1).first
      current_box = Ruby::Box.main

      # Fallback for calls outside IRB prompt
      if caller_loc.path != "(irb)"
        file_path = caller_loc.absolute_path || caller_loc.path
        return current_box.eval("eval('Kernel.require_relative(#{feature.dump})', nil, #{file_path.dump}, #{caller_loc.lineno})")
      end

      absolute_path = resolve_require_relative_path(feature)

      if !absolute_path.end_with?('.rb') || !File.exist?(absolute_path)
        file_path = File.join(Dir.pwd, "(irb)")
        return current_box.eval("eval('Kernel.require_relative(#{feature.dump})', nil, #{file_path.dump}, 1)")
      end

      reloadable_require_internal(absolute_path, current_box)
    end

    def resolve_require_relative_path(feature)
      absolute_path = File.expand_path(feature, Dir.pwd)
      return absolute_path unless File.extname(absolute_path).empty?

      dlext = RbConfig::CONFIG['DLEXT']
      ['.rb', ".#{dlext}"].each do |ext|
        candidate = absolute_path + ext
        return candidate if File.exist?(candidate)
      end

      absolute_path
    end

    def autoload(const, feature)
      IRB.conf[:__AUTOLOAD_FILES__] << feature
      Ruby::Box.main.eval("Kernel.autoload(:#{const}, #{feature.dump})")
    end
  end
end
