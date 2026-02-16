# frozen_string_literal: true
require "irb"

require_relative "helper"

module TestIRB
  class RubyLexTest < TestCase
    def setup
      save_encodings
    end

    def teardown
      restore_encodings
    end

    def test_local_variables_dependent_code
      lines = ["a /1#/ do", "2"]
      assert_indent_level(lines, 1)
      assert_code_block_open(lines, true)
      assert_indent_level(lines, 0, local_variables: [:a])
      assert_code_block_open(lines, false, local_variables: [:a])
    end

    def test_keyword_local_variables
      # Assuming `def f(if: 1, and: 2, ); binding.irb; end`
      local_variables = [:if, :and]
      lines = ['1 + 2']
      assert_indent_level(lines, 0, local_variables: local_variables)
      assert_code_block_open(lines, false, local_variables: local_variables)
    end

    def test_literal_ends_with_space
      assert_code_block_open(['% a'], true)
      assert_code_block_open(['% a '], false)
    end

    def test_literal_ends_with_newline
      assert_code_block_open(['%'], true)
      assert_code_block_open(['%', ''], false)
    end

    def test_should_continue
      assert_should_continue(['a'], false)
      assert_should_continue(['/a/'], false)
      assert_should_continue(['a;'], false)
      assert_should_continue(['<<A', 'A'], false)
      assert_should_continue(['a...'], false)
      assert_should_continue(['a\\'], true)
      assert_should_continue(['①\\'], true)
      assert_should_continue(['a.'], true)
      assert_should_continue(['a+'], true)
      assert_should_continue(['a; #comment', '', '=begin', 'embdoc', '=end', ''], false)
      assert_should_continue(['a+ #comment', '', '=begin', 'embdoc', '=end', ''], true)
    end

    def test_code_block_open_with_should_continue
      # syntax ok
      assert_code_block_open(['a'], false) # continue: false
      assert_code_block_open(['a\\'], true) # continue: true

      # recoverable syntax error code is not terminated
      assert_code_block_open(['a+'], true)

      # unrecoverable syntax error code is terminated
      assert_code_block_open(['.; a+'], false)
      assert_code_block_open(['@; a'], false)
      assert_code_block_open(['}'], false)
      assert_code_block_open(['(]'], false)
      assert_code_block_open(['end'], false)
    end

    def test_unterminated_heredoc_string_literal
      ['<<A;<<B', "<<A;<<B\n", "%W[\#{<<A;<<B", "%W[\#{<<A;<<B\n"].each do |code|
        string_literal = IRB::NestingParser.open_nestings(Prism.parse_lex(code)).last
        assert_equal('<<A', string_literal&.tok)
      end
    end

    def test_indent_level_with_heredoc_and_embdoc
      reference_code = <<~EOC.chomp
        if true
          hello
          p(
          )
      EOC
      code_with_heredoc = <<~EOC.chomp
        if true
          <<~A
          A
          p(
          )
      EOC
      code_with_embdoc = <<~EOC.chomp
        if true
        =begin
        =end
          p(
          )
      EOC
      expected = 1
      assert_indent_level(reference_code.lines, expected)
      assert_indent_level(code_with_heredoc.lines, expected)
      assert_indent_level(code_with_embdoc.lines, expected)
    end

    def test_assignment_expression
      ruby_lex = IRB::RubyLex.new

      [
        "foo = bar",
        "@foo = bar",
        "$foo = bar",
        "@@foo = bar",
        "::Foo = bar",
        "a::Foo = bar",
        "Foo = bar",
        "foo.bar = 1",
        "foo[1] = bar",
        "foo += bar",
        "foo -= bar",
        "foo ||= bar",
        "foo &&= bar",
        "foo, bar = 1, 2",
        "foo.bar=(1)",
        "foo; foo = bar",
        "foo; foo = bar; ;\n ;",
        "foo\nfoo = bar",
      ].each do |exp|
        assert(
          ruby_lex.assignment_expression?(exp, local_variables: []),
          "#{exp.inspect}: should be an assignment expression"
        )
      end

      [
        "foo",
        "foo.bar",
        "foo[0]",
        "foo = bar; foo",
        "foo = bar\nfoo",
      ].each do |exp|
        refute(
          ruby_lex.assignment_expression?(exp, local_variables: []),
          "#{exp.inspect}: should not be an assignment expression"
        )
      end
    end

    def test_assignment_expression_with_local_variable
      ruby_lex = IRB::RubyLex.new
      code = "a /1;x=1#/"
      refute(ruby_lex.assignment_expression?(code, local_variables: []), "#{code}: should not be an assignment expression")
      assert(ruby_lex.assignment_expression?(code, local_variables: [:a]), "#{code}: should be an assignment expression")
      refute(ruby_lex.assignment_expression?("", local_variables: [:a]), "empty code should not be an assignment expression")
    end

    def test_initialising_the_old_top_level_ruby_lex
      libdir = File.expand_path("../../lib", __dir__)
      reline_libdir = Gem.loaded_specs["reline"].full_gem_path + "/lib"
      assert_in_out_err(["-I#{libdir}", "-I#{reline_libdir}", "--disable-gems", "-W:deprecated"], <<~RUBY, [], /warning: constant ::RubyLex is deprecated/)
        require "irb"
        ::RubyLex.new(nil)
      RUBY
    end

    def test_syntax_check
      lex = RubyLex.new
      assert_equal(:valid, lex.check_code_syntax("b /c/; a /b\#{)", local_variables: [:a]))
      [
        'class A',
        'def f',
        'def f =',
        '1 +',
        'puts(',
        'puts(a,',
        'puts(x:',
        'puts(*',
        'puts(&',
        '[',
        '[1,',
        '{',
        '{x:',
        '{x:,',
        '[a, b ?',
        '[a, b ? c',
        '[a, b ? c :',
        'def f(a,',
        'class a', # followed by "\n::A; end"
        'a,b', # followed by "\n= v"
        'a,b,', # followed by "\nc = v"
        'a,B', # followed by "\n.c = v"
        'a,self', # followed by "\n.f = v"
        'a,$1', # followed by "\n.f = v"
        'p foo?:', # followed by "\nv"
        'x in A|{x:' # followed by "\nB}"
      ].each do |code|
        assert_include([:recoverable_error, :other_error], lex.check_code_syntax(code, local_variables: []), code)
      end
    end

    private

    def assert_indent_level(lines, expected, local_variables: [])
      indent_level, _continue, _code_block_open = check_state(lines, local_variables: local_variables)
      error_message = "Calculated the wrong number of indent level for:\n #{lines.join("\n")}"
      assert_equal(expected, indent_level, error_message)
    end

    def assert_should_continue(lines, expected, local_variables: [])
      _indent_level, continue, _code_block_open = check_state(lines, local_variables: local_variables)
      error_message = "Wrong result of should_continue for:\n #{lines.join("\n")}"
      assert_equal(expected, continue, error_message)
    end

    def assert_code_block_open(lines, expected, local_variables: [])
      if RUBY_ENGINE == 'truffleruby'
        omit "Remove me after https://github.com/ruby/prism/issues/2129 is addressed and adopted in TruffleRuby"
      end

      _indent_level, _continue, code_block_open = check_state(lines, local_variables: local_variables)
      error_message = "Wrong result of code_block_open for:\n #{lines.join("\n")}"
      assert_equal(expected, code_block_open, error_message)
    end

    def check_state(lines, local_variables: [])
      code = lines.map { |l| "#{l}\n" }.join # code should end with "\n"
      ruby_lex = IRB::RubyLex.new
      continue, opens, terminated = ruby_lex.check_code_state(code, local_variables: local_variables)
      indent_level = ruby_lex.calc_indent_level(opens)
      [indent_level, continue, !terminated]
    end
  end
end
