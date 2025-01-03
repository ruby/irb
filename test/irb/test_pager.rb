# frozen_string_literal: false
require 'irb/pager'

require_relative 'helper'

module TestIRB
  class PagerTest < TestCase
    def test_take_first_page
      assert_equal ['a' * 40, true], IRB::Pager.take_first_page(10, 4) {|io| io.puts 'a' * 41; raise 'should not reach here' }
      assert_equal ['a' * 39, false], IRB::Pager.take_first_page(10, 4) {|io| io.write 'a' * 39 }
      assert_equal ['a' * 39 + 'b', false], IRB::Pager.take_first_page(10, 4) {|io| io.write 'a' * 39 + 'b' }
      assert_equal ['a' * 39 + 'b', true], IRB::Pager.take_first_page(10, 4) {|io| io.write 'a' * 39 + 'bc' }
      assert_equal ["a\nb\nc\nd\n", false], IRB::Pager.take_first_page(10, 4) {|io| io.write "a\nb\nc\nd\n" }
      assert_equal ["a\nb\nc\nd\n", true], IRB::Pager.take_first_page(10, 4) {|io| io.write "a\nb\nc\nd\ne" }
      assert_equal ['a' * 15 + "\n" + 'b' * 20, true], IRB::Pager.take_first_page(10, 4) {|io| io.puts 'a' * 15; io.puts 'b' * 30 }
      assert_equal ["\e[31mA\e[0m" * 10 + 'x' * 30, true], IRB::Pager.take_first_page(10, 4) {|io| io.puts "\e[31mA\e[0m" * 10 + 'x' * 31; }
    end
  end

  class PageOverflowIOTest < TestCase
    def test_overflow
      actual_events = []
      overflow_callback = ->(lines) do
        actual_events << [:callback_called, lines]
      end
      out = IRB::Pager::PageOverflowIO.new(10, 4, overflow_callback)
      out.puts 'a' * 15
      out.write  'b' * 15

      actual_events << :before_write
      out.write 'c' * 1000
      actual_events << :after_write

      out.puts 'd' * 1000
      out.write 'e' * 1000

      expected_events = [
        :before_write,
        [:callback_called, ['a' * 10, 'a' * 5 + "\n",  'b' * 10, 'b' * 5 + 'c' * 5]],
        :after_write,
      ]
      assert_equal expected_events, actual_events

      expected_whole_content = 'a' * 15 + "\n" + 'b' * 15 + 'c' * 1000 + 'd' * 1000 + "\n" + 'e' * 1000
      assert_equal expected_whole_content, out.string
    end
  end
end
