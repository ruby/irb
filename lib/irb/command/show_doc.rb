# frozen_string_literal: true

module IRB
  module Command
    class ShowDoc < Base
      include RubyArgsExtractor

      category "Context"
      description "Look up documentation with RI."

      help_message <<~HELP_MESSAGE
        Usage: show_doc [name]

        When name is provided, IRB will look up the documentation for the given name.
        When no name is provided, a RI session will be started.

        Examples:

          show_doc
          show_doc Array
          show_doc Array#each

      HELP_MESSAGE

      def execute(arg)
        # Accept string literal for backward compatibility
        name = unwrap_string_literal(arg)

        if name.nil?
          if rdoc_provider.available?
            rdoc_provider.interactive
          else
            warn RDocDocumentProvider::NOT_INSTALLED_MESSAGE
          end
          return
        end

        IRB.doc_providers.each do |provider|
          document = provider.document(name)
          if document
            Pager.page_content(document)
            return
          end
        end

        if rdoc_provider.available?
          puts rdoc_provider.not_found_message(name)
        else
          warn RDocDocumentProvider::NOT_INSTALLED_MESSAGE
        end
        nil
      rescue SystemExit
        # RI's interactive session exits on Ctrl-C
        nil
      end

      private

      def rdoc_provider
        @rdoc_provider ||= IRB.doc_providers.find { |provider| provider.is_a?(RDocDocumentProvider) } || RDocDocumentProvider.new
      end
    end
  end
end
