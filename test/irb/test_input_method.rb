# frozen_string_literal: false

require "irb"

require_relative "helper"

module TestIRB
  class RelineInputMethodTest < TestCase
    def setup
      @conf_backup = IRB.conf.dup
      @completor = IRB::RegexpCompletor.new(nil)
      IRB.conf[:LC_MESSAGES] = IRB::Locale.new
      save_encodings
    end

    def teardown
      IRB.conf.replace(@conf_backup)
      restore_encodings
    end

    def test_initialization
      IRB::RelineInputMethod.new(completor: @completor)

      assert_nil Reline.completion_append_character
      assert_equal '', Reline.completer_quote_characters
      assert_equal IRB::InputMethod::BASIC_WORD_BREAK_CHARACTERS, Reline.basic_word_break_characters
      assert_equal @completor.method(:complete), Reline.completion_proc
      assert_equal @completor.method(:display_doc), Reline.dig_perfect_match_proc
    end

    def test_initialization_without_use_autocomplete
      original_show_doc_proc = Reline.dialog_proc(:show_doc)&.dialog_proc
      empty_proc = Proc.new {}
      Reline.add_dialog_proc(:show_doc, empty_proc)

      IRB.conf[:USE_AUTOCOMPLETE] = false

      IRB::RelineInputMethod.new(completor: @completor)

      refute Reline.autocompletion
      assert_equal empty_proc, Reline.dialog_proc(:show_doc).dialog_proc
    ensure
      Reline.add_dialog_proc(:show_doc, original_show_doc_proc, Reline::DEFAULT_DIALOG_CONTEXT)
    end

    def test_initialization_with_use_autocomplete
      original_show_doc_proc = Reline.dialog_proc(:show_doc)&.dialog_proc
      empty_proc = Proc.new {}
      Reline.add_dialog_proc(:show_doc, empty_proc)

      IRB.conf[:USE_AUTOCOMPLETE] = true

      IRB::RelineInputMethod.new(completor: @completor)

      assert Reline.autocompletion
      assert_not_nil Reline.dialog_proc(:show_doc)
      assert_not_equal empty_proc, Reline.dialog_proc(:show_doc).dialog_proc
    ensure
      Reline.add_dialog_proc(:show_doc, original_show_doc_proc, Reline::DEFAULT_DIALOG_CONTEXT)
    end

    def test_initialization_with_use_autocomplete_but_without_rdoc
      original_show_doc_proc = Reline.dialog_proc(:show_doc)&.dialog_proc
      empty_proc = Proc.new {}
      Reline.add_dialog_proc(:show_doc, empty_proc)

      IRB.conf[:USE_AUTOCOMPLETE] = true

      without_rdoc do
        IRB::RelineInputMethod.new(completor: @completor)
      end

      assert Reline.autocompletion
      # doesn't register show_doc dialog
      assert_equal empty_proc, Reline.dialog_proc(:show_doc).dialog_proc
    ensure
      Reline.add_dialog_proc(:show_doc, original_show_doc_proc, Reline::DEFAULT_DIALOG_CONTEXT)
    end
  end
end
