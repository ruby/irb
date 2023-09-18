# frozen_string_literal: false
require "pathname"
require "irb"
require "irb/completion/regexp_completor"

require_relative "helper"

module TestIRB
  class CompletionTest < TestCase
    def setup
      # make sure require completion candidates are not cached
      IRB::InputCompletor.class_variable_set(:@@files_from_load_path, nil)
    end

    def teardown
      IRB.conf[:MAIN_CONTEXT] = nil
    end

    def completion_candidates(target, bind)
      completor = IRB::InputCompletor::RegexpCompletor.new(target, '', '', bind: bind)
      completor.completion_candidates
    end

    def doc_namespace(target, bind)
      completor = IRB::InputCompletor::RegexpCompletor.new(target, '', '', bind: bind)
      completor.doc_namespace(target)
    end

    class MethodCompletionTest < CompletionTest
      def test_complete_string
        assert_include(completion_candidates("'foo'.up", binding), "'foo'.upcase")
        # completing 'foo bar'.up
        assert_include(completion_candidates("bar'.up", binding), "bar'.upcase")
        assert_equal("String.upcase", doc_namespace("'foo'.upcase", binding))
      end

      def test_complete_regexp
        assert_include(completion_candidates("/foo/.ma", binding), "/foo/.match")
        # completing /foo bar/.ma
        assert_include(completion_candidates("bar/.ma", binding), "bar/.match")
        assert_equal("Regexp.match", doc_namespace("/foo/.match", binding))
      end

      def test_complete_array
        assert_include(completion_candidates("[].an", binding), "[].any?")
        assert_equal("Array.any?", doc_namespace("[].any?", binding))
      end

      def test_complete_hash_and_proc
        # hash
        assert_include(completion_candidates("{}.an", binding), "{}.any?")
        assert_equal(["Proc.any?", "Hash.any?"], doc_namespace("{}.any?", binding))

        # proc
        assert_include(completion_candidates("{}.bin", binding), "{}.binding")
        assert_equal(["Proc.binding", "Hash.binding"], doc_namespace("{}.binding", binding))
      end

      def test_complete_numeric
        assert_include(completion_candidates("1.positi", binding), "1.positive?")
        assert_equal("Integer.positive?", doc_namespace("1.positive?", binding))

        assert_include(completion_candidates("1r.positi", binding), "1r.positive?")
        assert_equal("Rational.positive?", doc_namespace("1r.positive?", binding))

        assert_include(completion_candidates("0xFFFF.positi", binding), "0xFFFF.positive?")
        assert_equal("Integer.positive?", doc_namespace("0xFFFF.positive?", binding))

        assert_empty(completion_candidates("1i.positi", binding))
      end

      def test_complete_symbol
        assert_include(completion_candidates(":foo.to_p", binding), ":foo.to_proc")
        assert_equal("Symbol.to_proc", doc_namespace(":foo.to_proc", binding))
      end

      def test_complete_class
        assert_include(completion_candidates("String.ne", binding), "String.new")
        assert_equal("String.new", doc_namespace("String.new", binding))
      end
    end

    class RequireComepletionTest < CompletionTest
      def test_complete_require
        candidates = IRB::InputCompletor.retrieve_completion_candidates("'irb", "require ", "", bind: binding)
        %w['irb/init 'irb/ruby-lex].each do |word|
          assert_include candidates, word
        end
        # Test cache
        candidates = IRB::InputCompletor.retrieve_completion_candidates("'irb", "require ", "", bind: binding)
        %w['irb/init 'irb/ruby-lex].each do |word|
          assert_include candidates, word
        end
      end

      def test_complete_require_with_pathname_in_load_path
        temp_dir = Dir.mktmpdir
        File.write(File.join(temp_dir, "foo.rb"), "test")
        test_path = Pathname.new(temp_dir)
        $LOAD_PATH << test_path

        candidates = IRB::InputCompletor.retrieve_completion_candidates("'foo", "require ", "", bind: binding)
        assert_include candidates, "'foo"
      ensure
        $LOAD_PATH.pop if test_path
        FileUtils.remove_entry(temp_dir) if temp_dir
      end

      def test_complete_require_with_string_convertable_in_load_path
        temp_dir = Dir.mktmpdir
        File.write(File.join(temp_dir, "foo.rb"), "test")
        object = Object.new
        object.define_singleton_method(:to_s) { temp_dir }
        $LOAD_PATH << object

        candidates = IRB::InputCompletor.retrieve_completion_candidates("'foo", "require ", "", bind: binding)
        assert_include candidates, "'foo"
      ensure
        $LOAD_PATH.pop if object
        FileUtils.remove_entry(temp_dir) if temp_dir
      end

      def test_complete_require_with_malformed_object_in_load_path
        object = Object.new
        def object.to_s; raise; end
        $LOAD_PATH << object

        assert_nothing_raised do
          IRB::InputCompletor.retrieve_completion_candidates("'foo", "require ", "", bind: binding)
        end
      ensure
        $LOAD_PATH.pop if object
      end

      def test_complete_require_library_name_first
        candidates = IRB::InputCompletor.retrieve_completion_candidates("'csv", "require ", "", bind: binding)
        assert_equal "'csv", candidates.first
      end

      def test_complete_require_relative
        candidates = Dir.chdir(__dir__ + "/../..") do
          IRB::InputCompletor.retrieve_completion_candidates("'lib/irb", "require_relative ", "", bind: binding)
        end
        %w['lib/irb/init 'lib/irb/ruby-lex].each do |word|
          assert_include candidates, word
        end
        # Test cache
        candidates = Dir.chdir(__dir__ + "/../..") do
          IRB::InputCompletor.retrieve_completion_candidates("'lib/irb", "require_relative ", "", bind: binding)
        end
        %w['lib/irb/init 'lib/irb/ruby-lex].each do |word|
          assert_include candidates, word
        end
      end
    end

    class VariableCompletionTest < CompletionTest
      def test_complete_variable
        # Bug fix issues https://github.com/ruby/irb/issues/368
        # Variables other than `str_example` and `@str_example` are defined to ensure that irb completion does not cause unintended behavior
        str_example = ''
        @str_example = ''
        private_methods = ''
        methods = ''
        global_variables = ''
        local_variables = ''
        instance_variables = ''

        # suppress "assigned but unused variable" warning
        str_example.clear
        @str_example.clear
        private_methods.clear
        methods.clear
        global_variables.clear
        local_variables.clear
        instance_variables.clear

        assert_include(completion_candidates("str_examp", binding), "str_example")
        assert_equal("String", doc_namespace("str_example", binding))
        assert_equal("String.to_s", doc_namespace("str_example.to_s", binding))

        assert_include(completion_candidates("@str_examp", binding), "@str_example")
        assert_equal("String", doc_namespace("@str_example", binding))
        assert_equal("String.to_s", doc_namespace("@str_example.to_s", binding))
      end

      def test_complete_sort_variables
        xzy, xzy_1, xzy2 = '', '', ''

        xzy.clear
        xzy_1.clear
        xzy2.clear

        candidates = completion_candidates("xz", binding)
        assert_equal(%w[xzy xzy2 xzy_1], candidates)
      end
    end

    class ConstantCompletionTest < CompletionTest
      class Foo
        B3 = 1
        B1 = 1
        B2 = 1
      end

      def test_complete_constants
        assert_equal(["Foo"], completion_candidates("Fo", binding))
        assert_equal(["Foo::B1", "Foo::B2", "Foo::B3"], completion_candidates("Foo::B", binding))
        assert_equal(["Foo::B1.positive?"], completion_candidates("Foo::B1.pos", binding))

        assert_equal(["::Forwardable"], completion_candidates("::Fo", binding))
        assert_equal("Forwardable", doc_namespace("::Forwardable", binding))
      end
    end

    class PerfectMatchingTest < CompletionTest
      def setup
        # trigger display_perfect_matched_document to set up RDoc::RI::Driver.new
        IRB::InputCompletor::RegexpCompletor.display_perfect_matched_document("foo", bind: binding)
        @rdoc_ri_driver = IRB::InputCompletor::RegexpCompletor.instance_variable_get('@rdoc_ri_driver')

        @original_use_stdout = @rdoc_ri_driver.use_stdout
        # force the driver to use stdout so it doesn't start a pager and interrupt tests
        @rdoc_ri_driver.use_stdout = true
      end

      def teardown
        @rdoc_ri_driver.use_stdout = @original_use_stdout
      end

      def test_perfectly_matched_namespace_triggers_document_display
        omit unless has_rdoc_content?

        out, err = capture_output do
          IRB::InputCompletor::RegexpCompletor.display_perfect_matched_document("String", bind: binding)
        end

        assert_empty(err)

        assert_include(out, " S\bSt\btr\bri\bin\bng\bg")
      end

      def test_perfectly_matched_multiple_namespaces_triggers_document_display
        result = nil
        out, err = capture_output do
          result = IRB::InputCompletor::RegexpCompletor.display_perfect_matched_document("{}.nil?", bind: binding)
        end

        assert_empty(err)

        # check if there're rdoc contents (e.g. CI doesn't generate them)
        if has_rdoc_content?
          # if there's rdoc content, we can verify by checking stdout
          # rdoc generates control characters for formatting method names
          assert_include(out, "P\bPr\bro\boc\bc.\b.n\bni\bil\bl?\b?") # Proc.nil?
          assert_include(out, "H\bHa\bas\bsh\bh.\b.n\bni\bil\bl?\b?") # Hash.nil?
        else
          # this is a hacky way to verify the rdoc rendering code path because CI doesn't have rdoc content
          # if there are multiple namespaces to be rendered, PerfectMatchedProc renders the result with a document
          # which always returns the bytes rendered, even if it's 0
          assert_equal(0, result)
        end
      end

      def test_not_matched_namespace_triggers_nothing
        result = nil
        out, err = capture_output do
          result = IRB::InputCompletor::RegexpCompletor.display_perfect_matched_document("Stri", bind: binding)
        end

        assert_empty(err)
        assert_empty(out)
        assert_nil(result)
      end

      def test_perfect_matching_stops_without_rdoc
        result = nil

        out, err = capture_output do
          without_rdoc do
            result = IRB::InputCompletor::RegexpCompletor.display_perfect_matched_document("String", bind: binding)
          end
        end

        assert_empty(err)
        assert_not_match(/from ruby core/, out)
        assert_nil(result)
      end

      def test_perfect_matching_handles_nil_namespace
        out, err = capture_output do
          # symbol literal has `nil` doc namespace so it's a good test subject
          assert_nil(IRB::InputCompletor::RegexpCompletor.display_perfect_matched_document(":aiueo", bind: binding))
        end

        assert_empty(err)
        assert_empty(out)
      end

      private

      def has_rdoc_content?
        File.exist?(RDoc::RI::Paths::BASE)
      end
    end

    def test_complete_symbol
      symbols = %w"UTF-16LE UTF-7".map do |enc|
        "K".force_encoding(enc).to_sym
      rescue
      end
      symbols += [:aiueo, :"aiu eo"]
      candidates = completion_candidates(":a", binding)
      assert_include(candidates, ":aiueo")
      assert_not_include(candidates, ":aiu eo")
      assert_empty(completion_candidates(":irb_unknown_symbol_abcdefg", binding))
      # Do not complete empty symbol for performance reason
      assert_empty(completion_candidates(":", binding))
    end

    def test_complete_invalid_three_colons
      assert_empty(completion_candidates(":::A", binding))
      assert_empty(completion_candidates(":::", binding))
    end

    def test_complete_absolute_constants_with_special_characters
      assert_empty(completion_candidates("::A:", binding))
      assert_empty(completion_candidates("::A.", binding))
      assert_empty(completion_candidates("::A(", binding))
      assert_empty(completion_candidates("::A)", binding))
      assert_empty(completion_candidates("::A[", binding))
    end

    def test_complete_reserved_words
      candidates = completion_candidates("de", binding)
      %w[def defined?].each do |word|
        assert_include candidates, word
      end

      candidates = completion_candidates("__", binding)
      %w[__ENCODING__ __LINE__ __FILE__].each do |word|
        assert_include candidates, word
      end
    end

    def test_complete_methods
      obj = Object.new
      obj.singleton_class.class_eval {
        def public_hoge; end
        private def private_hoge; end

        # Support for overriding #methods etc.
        def methods; end
        def private_methods; end
        def global_variables; end
        def local_variables; end
        def instance_variables; end
      }
      bind = obj.instance_exec { binding }

      assert_include(completion_candidates("public_hog", bind), "public_hoge")
      assert_include(doc_namespace("public_hoge", bind), "public_hoge")

      assert_include(completion_candidates("private_hog", bind), "private_hoge")
      assert_include(doc_namespace("private_hoge", bind), "private_hoge")
    end
  end
end
