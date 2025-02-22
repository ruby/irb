# frozen_string_literal: true
require "irb"

require_relative "helper"

module TestIRB
  class EvalHistoryTest < TestCase
    def setup
      save_encodings
      IRB.instance_variable_get(:@CONF).clear
    end

    def teardown
      restore_encodings
    end

    def test_eval_history_is_disabled_by_default
      out, err = execute_lines(
        "a = 1",
        "__"
      )

      assert_empty(err)
      assert_match(/undefined local variable or method (`|')__'/, out)
    end

    def test_eval_history_can_be_retrieved_with_double_underscore
      out, err = execute_lines(
        "a = 1",
        "__",
        conf: { EVAL_HISTORY: 5 }
      )

      assert_empty(err)
      assert_match("=> 1\n" + "=> 1 1\n", out)
    end

    def test_eval_history_respects_given_limit
      out, err = execute_lines(
        "'foo'\n",
        "'bar'\n",
        "'baz'\n",
        "'xyz'\n",
        "__",
        conf: { EVAL_HISTORY: 4 }
      )

      assert_empty(err)
      # Because eval_history injects `__` into the history AND decide to ignore it, we only get <limit> - 1 results
      assert_match("2 \"bar\"\n" + "3 \"baz\"\n" + "4 \"xyz\"\n", out)
    end
  end
end
