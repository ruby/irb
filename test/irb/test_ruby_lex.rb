require 'test/unit'

class MockIO
  def initialize(params, &assertion)
    @params = params
    @assertion = assertion
  end

  def auto_indent(&block)
    result = block.call(*@params)
    @assertion.call(result)
  end
end

module TestIRB
  class TestRubyLex < Test::Unit::TestCase
    def test_indent_correctly_ending_with_newlines
      input_to_spaces = [
        [["[", ""], 1, 2],
        [["[", "]", ""], 2, 0],
        [["[[", "]", ""], 2, 2],
        [["[[", "]", "]", ""], 3, 0],
        [["[[[", "]", ""], 2, 4],
        [["[[[", "]", "]", ""], 3, 2],
        [["[[[", "]", "]", "]", ""], 4, 0],
        [["(((", ")", ")", ")", ""], 4, 0],
        [["{{{", "}", "}", "}", ""], 4, 0],
        [["[", "  # test", ""], 2, 2],
        [["<<FOO", ""], 1, 0],
        [["<<FOO", "bar", ""], 2, 0],
        [["[<<FOO]", "bar", ""], 2, 0],
        [["[<<FOO]", "bar", "FOO", ""], 3, 0],
        [["[<<FOO", "bar", ""], 2, 0],
      ]

      input_to_spaces.each do |lines, line_index, space_count|
        ruby_lex = RubyLex.new()
        io = MockIO.new([lines, line_index, nil, true]) do |auto_indent|
          assert_equal(space_count, auto_indent, "There was an failure parsing #{lines.inspect}")
        end
        ruby_lex.set_input(io)
        context = OpenStruct.new(auto_indent_mode: true)
        ruby_lex.set_auto_indent(context)
      end
    end

    def test_indent_correctly_not_ending_with_newlines
      input_to_spaces = [
        [["["], 0, nil],
        [["[["], 0, nil],
        [["[[", "    ]"], 1, 2],
        [["[[", "]"], 1, 2],
        [["[[", "]", "]"], 2, 0],
        [["[[", "]", "]"], 2, 0],
        [["[[["], 0, nil],
        [["[[[", "      ]"], 1, 4],
        [["[[[", "]", "]"], 2, 2],
        [["[[[", "]", "]", "]"], 3, 0],
      ]

      input_to_spaces.each do |lines, line_index, space_count|
        ruby_lex = RubyLex.new()
        io = MockIO.new([lines, line_index, lines.last.length, false]) do |auto_indent|
          assert_equal(space_count, auto_indent, "There was an failure parsing #{lines.inspect}")
        end
        ruby_lex.set_input(io)
        context = OpenStruct.new(auto_indent_mode: true)
        ruby_lex.set_auto_indent(context)
      end
    end
  end
end
