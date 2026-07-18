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
        require 'rdoc/ri/driver'

        driver = if output.remote?
          unless ShowDoc.const_defined?(:RemoteDriver, false)
            remote_driver = Class.new(RDoc::RI::Driver) do
              def initialize(options, output)
                @output = output
                super(options)
              end

              def page
                yield @output
              ensure
                @paging = false
              end

              def formatter(_io)
                require 'rdoc/markup/to_rdoc'
                RDoc::Markup::ToRdoc.new
              end
            end
            ShowDoc.const_set(:RemoteDriver, remote_driver)
          end

          opts = RDoc::RI::Driver.process_args([])
          ShowDoc::RemoteDriver.new(opts, output)
        else
          unless ShowDoc.const_defined?(:Ri, false)
            opts = RDoc::RI::Driver.process_args([])
            ShowDoc.const_set(:Ri, RDoc::RI::Driver.new(opts))
          end
          ShowDoc::Ri
        end

        if name.nil?
          driver.interactive
        else
          begin
            driver.display_name(name)
          rescue RDoc::RI::Error
            puts $!.message
          end
        end

        nil
      rescue LoadError, SystemExit
        warn "Can't display document because `rdoc` is not installed."
      end
    end
  end
end
