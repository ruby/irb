# frozen_string_literal: true

if !defined?(Ruby::Box) || !Ruby::Box.enabled?
  raise "ReloadableRequire requires Ruby::Box to be enabled"
end

require 'set'

module IRB
  # Provides reload-aware require functionality for IRB.
  #
  # This feature is experimental and requires Ruby::Box (Ruby 4.0+).
  #
  # Limitations:
  # - Native extensions cannot be reloaded (load doesn't support them)
  # - Constant redefinition warnings will appear on reload (uses load internally)

  module ReloadableRequire
    @reloadable_files = Set.new
    @autoload_features = {}

    class << self
      attr_reader :reloadable_files, :autoload_features

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

      def collect_autoloaded_files
        @autoload_features.each_value do |feature|
          resolved = $LOAD_PATH.resolve_feature_path(feature) rescue nil
          next unless resolved && resolved.first == :rb
          path = resolved[1]
          @reloadable_files << path if $LOADED_FEATURES.include?(path)
        end
      end
    end

    private

    def reloadable_require_internal(feature, caller_box)
      box = Ruby::Box.new
      box.eval("$LOAD_PATH.concat(#{caller_box.eval('$LOAD_PATH')})")
      box.eval("$LOADED_FEATURES.concat(#{caller_box.eval('$LOADED_FEATURES')})")

      ReloadableRequire.track_and_load_files(box.eval('$LOADED_FEATURES'), caller_box) { box.require(feature) }
    end

    def require(feature)
      caller_loc = caller_locations(1, 1).first
      return super unless caller_loc.path.end_with?("(irb)")

      reloadable_require_internal(feature, Ruby::Box.main)
    rescue LoadError
      super
    end

    def require_relative(feature)
      caller_loc = caller_locations(1, 1).first
      current_box = Ruby::Box.main

      unless caller_loc.path.end_with?("(irb)")
        file_path = caller_loc.absolute_path || caller_loc.path
        return current_box.eval("eval('Kernel.require_relative(#{feature.dump})', nil, #{file_path.dump}, #{caller_loc.lineno})")
      end

      reloadable_require_internal(File.expand_path(feature, Dir.pwd), current_box)
    rescue LoadError
      super
    end

    def autoload(const, feature)
      ReloadableRequire.autoload_features[const.to_s] = feature
      Ruby::Box.main.eval("Kernel.autoload(:#{const}, #{feature.dump})")
    end
  end
end
