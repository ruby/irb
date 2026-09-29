# frozen_string_literal: true

require_relative 'color'

module IRB
  # Returns the documentation providers consulted, in order, by the +show_doc+
  # command and by the documentation dialog of the autocompletion (Alt+d).
  #
  # By default the list only contains an RDocDocumentProvider, which looks up
  # RI data. Other backends can be added, for example from +.irbrc+; providers
  # earlier in the list take precedence:
  #
  #   IRB.doc_providers.unshift(MyDocProvider.new)
  #
  # A provider is any object that implements the following methods:
  #
  # +document(name)+::
  #   Returns the documentation of +name+ as a String, or +nil+ when the
  #   provider has nothing for +name+ so that the next provider is consulted.
  #   +name+ is written the way RI accepts it: <tt>"Array"</tt>,
  #   <tt>"Array#each"</tt>, <tt>"Array.new"</tt>, or <tt>"String.gsub"</tt>
  #   (the completion uses a dot even for instance methods). The returned
  #   String is shown through IRB::Pager and may contain ANSI escape sequences.
  #
  # +dialog_contents(name, width)+::
  #   Optional. Returns the preview shown in the documentation dialog as an
  #   Array of lines that fit in +width+ columns, or +nil+. The dialog skips
  #   providers that do not implement this method.
  class << self
    def doc_providers
      @doc_providers ||= [RDocDocumentProvider.new]
    end
  end

  # The default documentation provider. It looks up RI data (RDoc::RI::Driver),
  # including the directories in <tt>IRB.conf[:EXTRA_DOC_DIRS]</tt>.
  class RDocDocumentProvider
    NOT_INSTALLED_MESSAGE = "Can't display document because `rdoc` is not installed."

    # Returns true when RDoc can be loaded.
    def available?
      require 'rdoc'
      true
    rescue LoadError
      false
    end

    def document(name)
      document = retrieve_document(name)
      return unless document

      formatter = Color.colorable? ? RDoc::Markup::ToAnsi.new : RDoc::Markup::ToBs.new
      document.accept(formatter)
    end

    def dialog_contents(name, width)
      document = retrieve_document(name)
      return unless document

      formatter = RDoc::Markup::ToAnsi.new
      formatter.width = width
      document.accept(formatter).split("\n")
    end

    # Starts the interactive session of RI, as +show_doc+ without an argument does.
    def interactive
      driver.interactive
    end

    # Returns the message +show_doc+ prints when no provider knows +name+.
    # It reports the closest names RI knows, like the +ri+ command does.
    def not_found_message(name)
      matches = name.match?(/::|#|\./) ? driver.list_methods_matching(name) : []
      matches = driver.classes.keys.grep(/\A#{Regexp.escape(name)}/) if matches.empty?
      return "#{name} not found, maybe you meant:\n\n#{matches.sort.join("\n")}" unless matches.empty?

      driver.expand_name(name) # raises NotFoundError with "Did you mean?" for an unknown class
      "Nothing known about #{name}"
    rescue RDoc::RI::Driver::NotFoundError => e
      e.message
    end

    private

    def driver
      return @driver if defined?(@driver)

      require 'rdoc'
      require 'rdoc/ri/driver'
      options = {}
      extra_doc_dirs = IRB.conf[:EXTRA_DOC_DIRS]
      options[:extra_doc_dirs] = extra_doc_dirs unless extra_doc_dirs.nil? || extra_doc_dirs.empty?
      @driver = RDoc::RI::Driver.new(options)
    end

    # Returns an RDoc::Markup::Document for +name+, or nil when RI does not know it.
    def retrieve_document(name)
      return unless available?

      return retrieve_page(name) if name.match?(/\w:(\w|$)/)

      name = driver.expand_name(name)

      if name.match?(/#|\./)
        document = RDoc::Markup::Document.new
        driver.add_method(document, name)
      else
        found, klasses, includes, extends = driver.classes_and_includes_and_extends_for(name)
        if found.empty?
          document = RDoc::Markup::Document.new
          driver.add_method(document, name)
        else
          return driver.class_document(name, found, klasses, includes, extends)
        end
      end
      driver.expand_rdoc_refs_at_the_bottom(document) if driver.respond_to?(:expand_rdoc_refs_at_the_bottom)
      document
    rescue RDoc::RI::Driver::NotFoundError
      nil
    end

    # Returns the document of an RI page such as "ruby:syntax".
    def retrieve_page(name)
      store_name, page_name = name.split(':', 2)
      store = driver.stores.find { |s| s.source == store_name }
      return unless store

      pages = store.cache[:pages]
      unless pages.include?(page_name)
        candidates = pages.grep(/#{Regexp.escape(page_name)}\.[^.]+$/)
        return unless candidates.size == 1

        page_name = candidates.first
      end
      store.load_page(page_name).comment.parse
    end
  end
end
