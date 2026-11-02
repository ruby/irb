# frozen_string_literal: true
#
#   load.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
require_relative "../ext/loader"

module IRB
  # :stopdoc:

  module Command
    class LoaderCommand < Base
      include RubyArgsExtractor
      include IrbLoader

      def raise_cmd_argument_error
        raise CommandArgumentError.new("Please specify the file name.")
      end
    end

    class Load < LoaderCommand
      category "IRB"
      description "Load a Ruby file."

      def execute(arg)
        args, kwargs = ruby_args(arg)
        execute_internal(*args, **kwargs)
      end

      def execute_internal(file_name = nil, priv = nil)
        raise_cmd_argument_error unless file_name
        irb_load(file_name, priv)
      end
    end

    class Require < LoaderCommand
      category "IRB"
      description "Require a Ruby file."

      def execute(arg)
        args, kwargs = ruby_args(arg)
        execute_internal(*args, **kwargs)
      end

      def execute_internal(file_name = nil)
        raise_cmd_argument_error unless file_name

        return false if already_loaded?(file_name)

        case file_name
        when /\.rb$/
          begin
            if irb_load(file_name)
              $".push file_name
              return true
            end
          rescue LoadError
          end
        when /\.(so|o|sl)$/
          return require(file_name)
        end

        begin
          irb_load(f = file_name + ".rb")
          $".push f
          true
        rescue LoadError
          require(file_name)
        end
      end

      private

      # $" holds the names irb_require pushed and the absolute paths that
      # Kernel#require loaded from a $LOAD_PATH directory.
      def already_loaded?(file_name)
        names = [file_name, "#{file_name}.rb", "#{file_name}.o"]
        paths = $LOAD_PATH.flat_map do |dir|
          dir = dir.to_s
          names.map { |name| File.expand_path(File.join(dir, name)) }
        end
        $".any? { |f| names.include?(f) || paths.include?(f) }
      end
    end

    class Source < LoaderCommand
      category "IRB"
      description "Loads a given file in the current session."

      def execute(arg)
        args, kwargs = ruby_args(arg)
        execute_internal(*args, **kwargs)
      end

      def execute_internal(file_name = nil)
        raise_cmd_argument_error unless file_name

        source_file(file_name)
      end
    end
  end
  # :startdoc:
end
