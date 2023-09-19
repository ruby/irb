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
      # This method is always called before retrieve_completion_doc_namespace and display_perfect_matched_document.
      # To use preposing, postposing and binding information in those methods,
      # We need to store them as an instance of completor_class into @completor.
      @completor = completor_class.new(target, preposing, postposing, bind: bind)
      @completor.completion_candidates
    end

    def self.retrieve_completion_doc_namespace(target)
      @completor.doc_namespace(target)
    end

    def self.display_perfect_matched_document(matched)
      begin
        require 'rdoc'
      rescue LoadError
        return
      end

      if matched =~ /\A(?:::)?RubyVM/ and not ENV['RUBY_YES_I_AM_NOT_A_NORMAL_USER']
        IRB.__send__(:easter_egg)
        return
      end

      @rdoc_ri_driver ||= RDoc::RI::Driver.new

      namespace = @completor.doc_namespace(matched)
      return unless namespace

      if namespace.is_a?(Array)
        out = RDoc::Markup::Document.new
        namespace.each do |m|
          begin
            @rdoc_ri_driver.add_method(out, m)
          rescue RDoc::RI::Driver::NotFoundError
          end
        end
        @rdoc_ri_driver.display(out)
      else
        begin
          @rdoc_ri_driver.display_names([namespace])
        rescue RDoc::RI::Driver::NotFoundError
        end
      end
    end
  end
end
