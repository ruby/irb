# frozen_string_literal: false
#
#   irb/completion.rb -
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#       From Original Idea of shugo@ruby-lang.org
#

require_relative 'ruby-lex'

module IRB
  module InputCompletor # :nodoc:

    BASIC_WORD_BREAK_CHARACTERS = " \t\n`><=;|&{("

    GEM_PATHS =
      if defined?(Gem::Specification)
        Gem::Specification.latest_specs(true).map { |s|
          s.require_paths.map { |p|
            if File.absolute_path?(p)
              p
            else
              File.join(s.full_gem_path, p)
            end
          }
        }.flatten
      else
        []
      end.freeze

    def self.retrieve_gem_and_system_load_path
      candidates = (GEM_PATHS | $LOAD_PATH)
      candidates.map do |p|
        if p.respond_to?(:to_path)
          p.to_path
        else
          String(p) rescue nil
        end
      end.compact.sort
    end

    def self.retrieve_files_to_require_from_load_path
      @@files_from_load_path ||=
        (
          shortest = []
          rest = retrieve_gem_and_system_load_path.each_with_object([]) { |path, result|
            begin
              names = Dir.glob("**/*.{rb,#{RbConfig::CONFIG['DLEXT']}}", base: path)
            rescue Errno::ENOENT
              nil
            end
            next if names.empty?
            names.map! { |n| n.sub(/\.(rb|#{RbConfig::CONFIG['DLEXT']})\z/, '') }.sort!
            shortest << names.shift
            result.concat(names)
          }
          shortest.sort! | rest
        )
    end

    def self.retrieve_files_to_require_relative_from_current_dir
      @@files_from_current_dir ||= Dir.glob("**/*.{rb,#{RbConfig::CONFIG['DLEXT']}}", base: '.').map { |path|
        path.sub(/\.(rb|#{RbConfig::CONFIG['DLEXT']})\z/, '')
      }
    end

    def self.completor_class
      require_relative 'completion/regexp_completor'
      RegexpCompletor
    end

    def self.retrieve_completion_candidates(target, preposing, postposing, bind:)
      @completor = completor_class.new(target, preposing, postposing, bind: bind)
      @completor.completion_candidates
    end

    def self.retrieve_completion_doc_namespace(target)
      # This method is always called after retrieve_completion_candidates is called.
      @completor.doc_namespace(target)
    end
  end
end
