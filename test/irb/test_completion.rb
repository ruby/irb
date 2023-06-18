# frozen_string_literal: false
require "pathname"
require "irb"

require_relative "helper"

module TestIRB
  class CompletionTest < TestCase
    def setup
      # make sure require completion candidates are not cached
      IRB::InputCompletor.class_variable_set(:@@files_from_load_path, nil)
    end

    TestCompletionProcContext = Struct.new(:workspace)

    def call_completion_proc(target, preposing, postposing, bind: nil)
      main_context = IRB.conf[:MAIN_CONTEXT]
      IRB.conf[:MAIN_CONTEXT] = TestCompletionProcContext.new(IRB::WorkSpace.new(bind || Object.new))
      candidates = IRB::InputCompletor::CompletionProc.call target, preposing, postposing
      yield if block_given?
      candidates
    ensure
      IRB::InputCompletor.class_variable_set :@@previous_completion_data, nil
      IRB.conf[:MAIN_CONTEXT] = main_context
    end

    def completion_candidates(code, bind:)
      call_completion_proc(code, '', '', bind: bind)
    end

    def doc_namespace(code, bind:)
      completion_data = IRB::InputCompletor.retrieve_completion_data(code, bind: bind)
      IRB::InputCompletor.retrieve_doc_namespace(code, completion_data, bind: bind)
    end

    class MethodCompletionTest < CompletionTest
      def test_complete_string
        assert_include(call_completion_proc("'foo'.up", "", "", bind: binding), "'foo'.upcase")
        assert_include(call_completion_proc("bar'.up", "'foo ", "", bind: binding), "bar'.upcase")
        assert_equal("String.upcase", doc_namespace("'foo'.upcase", bind: binding))
      end

      def test_complete_regexp
        assert_include(call_completion_proc("/foo/.ma", "" ,"", bind: binding), "/foo/.match")
        assert_include(call_completion_proc("bar/.ma", "/foo ", "", bind: binding), "bar/.match")
        assert_equal("Regexp.match", doc_namespace("/foo/.match", bind: binding))
      end

      def test_complete_array
        assert_include(completion_candidates("[].an", bind: binding), "[].any?")
        assert_include(completion_candidates("[a].an", bind: binding), "[a].any?")
        assert_include(completion_candidates("[*a].an", bind: binding), "[*a].any?")
        assert_equal("Array.any?", doc_namespace("[].any?", bind: binding))
      end

      def test_complete_hash
        assert_include(completion_candidates("{}.an", bind: binding), "{}.any?")
        assert_include(completion_candidates("{a:1}.an", bind: binding), "{a:1}.any?")
        assert_include(completion_candidates("{**a}.an", bind: binding), "{**a}.any?")
        assert_equal("Hash.any?", doc_namespace("{}.any?", bind: binding))
      end

      def test_complete_proc
        assert_include(completion_candidates("->{}.bin", bind: binding), "->{}.binding")
        assert_equal("Proc.binding", doc_namespace("->{}.binding", bind: binding))
      end

      def test_complete_keywords
        assert_include(completion_candidates("nil.to_", bind: binding), "nil.to_a")
        assert_equal("NilClass.to_a", doc_namespace("nil.to_a", bind: binding))

        assert_include(completion_candidates("true.to_", bind: binding), "true.to_s")
        assert_equal("TrueClass.to_s", doc_namespace("true.to_s", bind: binding))

        assert_include(completion_candidates("false.to_", bind: binding), "false.to_s")
        assert_equal("FalseClass.to_s", doc_namespace("false.to_s", bind: binding))
      end

      def test_complete_numeric
        assert_include(completion_candidates("1.positi", bind: binding), "1.positive?")
        assert_equal("Integer.positive?", doc_namespace("1.positive?", bind: binding))

        assert_include(completion_candidates("1r.positi", bind: binding), "1r.positive?")
        assert_equal("Rational.positive?", doc_namespace("1r.positive?", bind: binding))

        assert_include(completion_candidates("0xFFFF.positi", bind: binding), "0xFFFF.positive?")
        assert_equal("Integer.positive?", doc_namespace("0xFFFF.positive?", bind: binding))

        assert_empty(completion_candidates("1i.positi", bind: binding))
      end

      def test_complete_symbol
        assert_include(completion_candidates(":foo.to_p", bind: binding), ":foo.to_proc")
        assert_equal("Symbol.to_proc", doc_namespace(":foo.to_proc", bind: binding))
      end

      def test_complete_class
        assert_include(completion_candidates("String.ne", bind: binding), "String.new")
        assert_equal("String.new", doc_namespace("String.new", bind: binding))
      end
    end

    class RequireComepletionTest < CompletionTest
      def test_complete_require
        candidates = call_completion_proc("'irb", "require ", "")
        %w['irb/init 'irb/ruby-lex].each do |word|
          assert_include candidates, word
        end
        # Test cache
        candidates = call_completion_proc("'irb", "require ", "")
        %w['irb/init 'irb/ruby-lex].each do |word|
          assert_include candidates, word
        end
      end

      def test_complete_require_with_pathname_in_load_path
        temp_dir = Dir.mktmpdir
        File.write(File.join(temp_dir, "foo.rb"), "test")
        test_path = Pathname.new(temp_dir)
        $LOAD_PATH << test_path

        candidates = call_completion_proc("'foo", "require ", "")
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

        candidates = call_completion_proc("'foo", "require ", "")
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
          call_completion_proc("'foo", "require ", "")
        end
      ensure
        $LOAD_PATH.pop if object
      end

      def test_complete_require_library_name_first
        candidates = call_completion_proc("'csv", "require ", "")
        assert_equal "'csv", candidates.first
      end

      def test_complete_require_relative
        candidates = Dir.chdir(__dir__ + "/../..") do
          call_completion_proc("'lib/irb", "require_relative ", "")
        end
        %w['lib/irb/init 'lib/irb/ruby-lex].each do |word|
          assert_include candidates, word
        end
        # Test cache
        candidates = Dir.chdir(__dir__ + "/../..") do
          call_completion_proc("'lib/irb", "require_relative ", "")
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

        assert_include(completion_candidates("str_examp", bind: binding), "str_example")
        assert_equal("String", doc_namespace("str_example", bind: binding))
        assert_equal("String.to_s", doc_namespace("str_example.to_s", bind: binding))

        assert_include(completion_candidates("@str_examp", bind: binding), "@str_example")
        assert_equal("String", doc_namespace("@str_example", bind: binding))
        assert_equal("String.to_s", doc_namespace("@str_example.to_s", bind: binding))
      end

      def test_complete_sort_variables
        xzy, xzy_1, xzy2 = '', '', ''

        xzy.clear
        xzy_1.clear
        xzy2.clear

        candidates = completion_candidates("xz", bind: binding)
        assert_equal(%w[xzy xzy2 xzy_1], candidates)
      end

      def test_localvar_dependent
        bind = eval('lvar = 1; binding')
        assert_include(call_completion_proc('lvar&.', 'non_lvar /%i&i/i; ', '', bind: bind), 'lvar&.abs')
        assert_include(call_completion_proc('lvar&.', 'lvar /%i&i/i; ', '', bind: bind), 'lvar&.sort')
      end
    end

    class ConstantCompletionTest < CompletionTest
      class Foo
        B3 = 1
        B1 = 1
        B2 = 1
      end

      def test_complete_constants
        assert_include(completion_candidates("IRB::Input", bind: binding), "IRB::InputCompletor")
        assert_not_include(completion_candidates("Input", bind: binding), "InputCompletor")

        assert_include(completion_candidates("Fo", bind: binding), "Foo")
        assert_include(completion_candidates("Fo", bind: binding), "Forwardable")
        assert_include(completion_candidates("Con", bind: binding), "ConstantCompletionTest")
        assert_include(completion_candidates("Var", bind: binding), "VariableCompletionTest")

        assert_equal(["Foo::B1", "Foo::B2", "Foo::B3"], completion_candidates("Foo::B", bind: binding))
        assert_equal(["Foo::B1.positive?"], completion_candidates("Foo::B1.pos", bind: binding))

        assert_equal(["::Forwardable"], completion_candidates("::Fo", bind: binding))
        assert_equal("Forwardable", doc_namespace("::Forwardable", bind: binding))
      end
    end

    class NestedCompletionTest < CompletionTest
      def assert_preposing_completable(preposing)
        assert_include(call_completion_proc('1.', preposing, ''), '1.abs')
      end

      def test_paren_bracket_brace
        assert_preposing_completable('(')
        assert_preposing_completable('[')
        assert_preposing_completable('a(')
        assert_preposing_completable('a[')
        assert_preposing_completable('a{')
        assert_preposing_completable('{x:')
        assert_preposing_completable('[([{x:([(')
      end

      def test_embexpr
        assert_preposing_completable('"#{')
        assert_preposing_completable('/#{')
        assert_preposing_completable('`#{')
        assert_preposing_completable('%(#{')
        assert_preposing_completable('%)#{')
        assert_preposing_completable('%!#{')
        assert_preposing_completable('%r[#{')
        assert_preposing_completable('%I]#{')
        assert_preposing_completable('%W!#{')
        assert_preposing_completable('%Q@#{')
      end

      def test_control_syntax
        assert_preposing_completable('if true;')
        assert_preposing_completable('def f;')
        assert_preposing_completable('def f(a =')
        assert_preposing_completable('case ')
        assert_preposing_completable('case a; when ')
        assert_preposing_completable('case a; when b;')
        assert_preposing_completable('p do;')
        assert_preposing_completable('begin;')
        assert_preposing_completable('p do; rescue;')
        assert_preposing_completable('1 rescue ')
      end
    end

    class PerfectMatchingTest < CompletionTest
      def setup
        # trigger PerfectMatchedProc to set up RDocRIDriver constant
        IRB::InputCompletor::PerfectMatchedProc.("foo", bind: binding)

        @original_use_stdout = IRB::InputCompletor::RDocRIDriver.use_stdout
        # force the driver to use stdout so it doesn't start a pager and interrupt tests
        IRB::InputCompletor::RDocRIDriver.use_stdout = true
      end

      def teardown
        IRB::InputCompletor::RDocRIDriver.use_stdout = @original_use_stdout
      end

      def test_perfectly_matched_namespace_triggers_document_display
        omit unless has_rdoc_content?

        out, err = capture_output do
          call_completion_proc("St", '', '', bind: binding) do
            IRB::InputCompletor::PerfectMatchedProc.("String", bind: binding)
          end
        end

        assert_empty(err)

        assert_include(out, " S\bSt\btr\bri\bin\bng\bg")
      end

      def test_not_matched_namespace_triggers_nothing
        result = nil
        out, err = capture_output do
          call_completion_proc("St", '', '', bind: binding) do
            result = IRB::InputCompletor::PerfectMatchedProc.("Stri", bind: binding)
          end
        end

        assert_empty(err)
        assert_empty(out)
        assert_nil(result)
      end

      def test_perfect_matching_stops_without_rdoc
        result = nil

        out, err = capture_output do
          without_rdoc do
            result = IRB::InputCompletor::PerfectMatchedProc.("String", bind: binding)
          end
        end

        assert_empty(err)
        assert_not_match(/from ruby core/, out)
        assert_nil(result)
      end

      def test_perfect_matching_handles_nil_namespace
        out, err = capture_output do
          # symbol literal has `nil` doc namespace so it's a good test subject
          assert_nil(IRB::InputCompletor::PerfectMatchedProc.(":aiueo", bind: binding))
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
      candidates = completion_candidates(":a", bind: binding)
      assert_include(candidates, ":aiueo")
      assert_not_include(candidates, ":aiu eo")
      # Do not complete empty symbol for performance reason
      assert_empty(completion_candidates(":", bind: binding))
    end

    def test_complete_invalid_three_colons
      assert_empty(completion_candidates(":::A", bind: binding))
      assert_empty(completion_candidates(":::", bind: binding))
    end

    def test_complete_reserved_words
      candidates = completion_candidates("de", bind: binding)
      %w[def defined?].each do |word|
        assert_include candidates, word
      end

      candidates = completion_candidates("__", bind: binding)
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

      assert_include(completion_candidates("public_hog", bind: bind), "public_hoge")
      assert_include(doc_namespace("public_hoge", bind: bind), "public_hoge")

      assert_include(completion_candidates("private_hog", bind: bind), "private_hoge")
      assert_include(doc_namespace("private_hoge", bind: bind), "private_hoge")
    end
  end
end
