# frozen_string_literal: false
require "irb"
begin
  require "rdoc"
rescue LoadError
end
require_relative "helper"

module TestIRB
  class DocProviderTest < TestCase
    def setup
      @conf_backup = IRB.conf.dup
      IRB.init_config(nil)
    end

    def teardown
      IRB.conf.replace(@conf_backup)
    end

    def test_default_providers
      assert_kind_of(Array, IRB.doc_providers)
      assert(IRB.doc_providers.any? { |provider| provider.is_a?(IRB::RDocDocumentProvider) })
    end
  end

  class RDocDocumentProviderTest < TestCase
    def setup
      @conf_backup = IRB.conf.dup
      IRB.init_config(nil)
      @provider = IRB::RDocDocumentProvider.new
    end

    def teardown
      IRB.conf.replace(@conf_backup)
    end

    def test_available
      assert(@provider.available?)
      without_rdoc do
        refute(@provider.available?)
      end
    end

    def test_document_returns_nil_without_rdoc
      without_rdoc do
        assert_nil(@provider.document("String#gsub"))
        assert_nil(@provider.dialog_contents("String.gsub", 40))
      end
    end

    def test_document_returns_nil_for_unknown_name
      assert_nil(@provider.document("Foo#bar"))
      assert_nil(@provider.dialog_contents("Foo.bar", 40))
    end

    def test_not_found_message_for_unknown_name
      assert_equal("Nothing known about Foo#bar", @provider.not_found_message("Foo#bar"))
      assert_equal("Nothing known about Foo", @provider.not_found_message("Foo"))
    end

    def test_not_found_message_without_ri_data
      provider = IRB::RDocDocumentProvider.new
      provider.instance_variable_set(:@driver, RDoc::RI::Driver.new(use_system: false, use_site: false, use_home: false, use_gems: false))

      assert_equal("Nothing known about String#gsub", provider.not_found_message("String#gsub"))
      assert_equal("Nothing known about String", provider.not_found_message("String"))
    end

    def test_document
      omit "This test requires RI data" unless has_rdoc_content?

      document = @provider.document("Array.new")
      assert_include(strip_formatting(document), "Array.new")

      document = @provider.document("String")
      assert_include(strip_formatting(document), "String < Object")
    end

    def test_dialog_contents
      omit "This test requires RI data" unless has_rdoc_content?

      contents = @provider.dialog_contents("Array.new", 40)
      assert_kind_of(Array, contents)
      assert_include(strip_formatting(contents.join("\n")), "Array.new")
    end

    def test_not_found_message_suggests_similar_names
      omit "This test requires RI data" unless has_rdoc_content?

      message = @provider.not_found_message("String#gsu")
      assert_include(message, "maybe you meant")
      assert_include(message, "String#gsub")

      assert_include(@provider.not_found_message("String#zzz"), "Nothing known about String#zzz")
    end

    private

    def has_rdoc_content?
      File.exist?(RDoc::RI::Paths::BASE)
    end

    # remove the bold formatting of RDoc::Markup::ToBs and RDoc::Markup::ToAnsi
    def strip_formatting(text)
      text.gsub(/.\x08/, "").gsub(/\e\[[0-9;]*m/, "")
    end
  end if defined?(RDoc)
end
