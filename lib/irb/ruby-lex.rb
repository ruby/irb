# frozen_string_literal: true
#
#   irb/ruby-lex.rb - ruby lexcal analyzer
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

require "prism"
require "jruby" if RUBY_ENGINE == "jruby"
require_relative "nesting_parser"

module IRB
  # :stopdoc:
  class RubyLex
    LTYPE_TOKENS = %i[
      on_heredoc_beg on_tstring_beg
      on_regexp_beg on_symbeg on_backtick
      on_symbols_beg on_qsymbols_beg
      on_words_beg on_qwords_beg
    ]

    RESERVED_WORDS = %i[
      __ENCODING__ __LINE__ __FILE__
      BEGIN END
      alias and
      begin break
      case class
      def defined? do
      else elsif end ensure
      false for
      if in
      module
      next nil not
      or
      redo rescue retry return
      self super
      then true
      undef unless until
      when while
      yield
    ]

    class TerminateLineInput < StandardError
      def initialize
        super("Terminate Line Input")
      end
    end

    def check_code_state(code, local_variables:)
      parse_lex_result = Prism.parse_lex(code, scopes: [local_variables])

      opens = NestingParser.open_nestings(parse_lex_result)
      lines = code.lines
      tokens = parse_lex_result.value[1].map(&:first).sort_by {|t| t.location.start_offset }
      continue = should_continue?(tokens, lines.last, lines.size)
      [continue, opens, code_terminated?(code, continue, opens, local_variables: local_variables)]
    end

    def code_terminated?(code, continue, opens, local_variables:)
      case check_code_syntax(code, local_variables: local_variables)
      when :unrecoverable_error
        true
      when :recoverable_error
        false
      when :other_error
        opens.empty? && !continue
      when :valid
        !continue
      end
    end

    def assignment_expression?(code, local_variables:)
      # Parse the code and check if the last of possibly multiple
      # expressions is an assignment node.
      program_node = Prism.parse(code, scopes: [local_variables]).value
      node = program_node.statements.body.last
      case node
      when nil
        # Empty code, comment-only code or invalid code
        false
      when Prism::CallNode
        # a.b = 1, a[b] = 1
        # Prism::CallNode#equal_loc is only available in prism >= 1.7.0
        if node.name == :[]=
          # Distinguish between `a[k] = v` from `a.[]= k, v`, `a.[]=(k, v)`
          node.opening == '['
        else
          node.name.end_with?('=')
        end
      when Prism::MatchWriteNode
        # /(?<lvar>)/ =~ a, Class name is *WriteNode but not an assignment.
        false
      else
        # a = 1, @a = 1, $a = 1, @@a = 1, A = 1, a += 1, a &&= 1, a.b += 1, and so on
        node.class.name.match?(/WriteNode/)
      end
    end

    def should_continue?(tokens, line, line_num)
      # Check if the line ends with \\. Then IRB should continue reading next line.
      # Space and backslash are not included in Prism token, so find trailing text after last non-newline token position.
      trailing = line
      tokens.reverse_each do |t|
        break if t.location.start_line < line_num
        if t.location.start_line == line_num &&
            t.location.end_line == line_num &&
            t.type != :IGNORED_NEWLINE &&
            t.type != :NEWLINE &&
            t.type != :EOF
          trailing = line.byteslice(t.location.end_column..)
          break
        end
      end
      return true if trailing.match?(/\A\s*\\\n?\z/)

      # "1 + \n" and "foo.\n" should continue.
      pos = tokens.size - 1
      ignored_newline_found = false
      while pos >= 0
        case tokens[pos].type
        when :EMBDOC_BEGIN, :EMBDOC_LINE, :EMBDOC_END, :COMMENT, :EOF
          pos -= 1
        when :IGNORED_NEWLINE
          pos -= 1
          ignored_newline_found = true
        else
          break
        end
      end

      # If IGNORED_NEWLINE token is following non-newline non-semicolon token, it should continue.
      # Special case: treat `1..` and `1...` as not continuing.
      ignored_newline_found && pos >= 0 && !%i[DOT_DOT DOT_DOT_DOT NEWLINE SEMICOLON].include?(tokens[pos].type)
    end

    def check_code_syntax(code, local_variables:)
      result = Prism.lex(code, scopes: [local_variables])
      return :valid if result.success?

      # Get the token excluding trailing comments and newlines
      # to compare error location with the last or second-last meaningful token location
      tokens = result.value.map(&:first)
      until tokens.empty?
        case tokens.last.type
        when :COMMENT, :NEWLINE, :IGNORED_NEWLINE, :EMBDOC_BEGIN, :EMBDOC_LINE, :EMBDOC_END, :EOF
          tokens.pop
        else
          break
        end
      end

      unknown = false
      result.errors.each do |error|
        case error.message
        when /unexpected character literal|incomplete expression at|unexpected .%.|too short escape sequence/i
          # Ignore these errors. Likely to appear only at the end of code.
          # `[a, b ?` unexpected character literal, incomplete expression at
          # `p a, %`  unexpected '%'
          # `/\u`     too short escape sequence
        when /unexpected write target/i
          # `a,b` recoverable by `=v`
          # `a,b,` recoverable by `c=v`
          tok = tokens.last
          tok = tokens[-2] if tok&.type == :COMMA
          return :unrecoverable_error if tok && error.location.end_offset < tok.location.end_offset
        when /(invalid|unexpected) (?:break|next|redo)/i
          # Hard to check correctly, so treat it as always recoverable.
          # `(break;1)` recoverable by `.f while true`
        when / meets end of file|unexpected end-of-input|unterminated |cannot parse|could not parse/i
          # These are recoverable errors if there is no other unrecoverable error
          # `/aaa`    unterminated regexp meets end of file
          # `def f`   unexpected end-of-input
          # `"#{`     unterminated string
          # `:"aa`    cannot parse the string part
          # `def f =` could not parse the endless method body
        when /is not allowed|unexpected .+ ignoring it/i
          # `@@` `$--` is not allowed
          # `)`, `end` unexpected ')', ignoring it
          return :unrecoverable_error
        when /unexpected |invalid |dynamic constant assignment|can't set variable|can't change the value|is not valid to get|variable capture in alternative pattern/i
          # Likely to be unrecoverable except when the error is at the last token location.
          # Unexpected: `class a`, `tap(&`, `def f(a,`
          # Invalid: `a ? b :`, `/\u{`, `"\M-`
          # `a,B`        recoverable by `.c=v` dynamic constant assignment
          # `a,$1`       recoverable by `.f=v` Can't set variable
          # `a,self`     recoverable by `.f=v` Can't change the value of self
          # `p foo?:`    recoverable by `v`    is not valid to get
          # `x in 1|{x:` recoverable by `1}`   variable capture in alternative pattern
          return :unrecoverable_error if tokens.last && error.location.end_offset <= tokens.last.location.start_offset
        else
          unknown = true
        end
      end
      unknown ? :other_error : :recoverable_error
    end

    def calc_indent_level(opens)
      indent_level = 0
      opens.each_with_index do |elem, index|
        case elem.event
        when :on_heredoc_beg
          if opens[index + 1]&.event != :on_heredoc_beg
            if elem.tok.match?(/^<<[~-]/)
              indent_level += 1
            else
              indent_level = 0
            end
          end
        when :on_tstring_beg, :on_regexp_beg, :on_symbeg, :on_backtick
          # No indent: "", //, :"", ``
          # Indent: %(), %r(), %i(), %x()
          indent_level += 1 if elem.tok.start_with? '%'
        when :on_embdoc_beg
          indent_level = 0
        else
          indent_level += 1 unless elem.tok == 'alias' || elem.tok == 'undef'
        end
      end
      indent_level
    end

    FREE_INDENT_NESTINGS = %i[on_tstring_beg on_backtick on_regexp_beg on_symbeg]

    def free_indent_nesting_element?(elem)
      FREE_INDENT_NESTINGS.include?(elem&.event)
    end

    # Calculates the difference of pasted code's indent and indent calculated from tokens
    def indent_difference(lines, line_results, line_index)
      loop do
        prev_opens, _next_opens, min_depth = line_results[line_index]
        open_elem = prev_opens.last
        if !open_elem || (open_elem.event != :on_heredoc_beg && !free_indent_nesting_element?(open_elem))
          # If the leading whitespace is an indent, return the difference
          indent_level = calc_indent_level(prev_opens.take(min_depth))
          calculated_indent = 2 * indent_level
          actual_indent = lines[line_index][/^ */].size
          return actual_indent - calculated_indent
        elsif open_elem.event == :on_heredoc_beg && open_elem.tok.match?(/^<<[^-~]/)
          return 0
        end
        # If the leading whitespace is not an indent but part of a multiline token
        # Calculate base_indent of the multiline token's beginning line
        line_index = open_elem.pos[0] - 1
      end
    end

    def process_indent_level(parse_lex_result, lines, line_index, is_newline)
      line_results = NestingParser.parse_by_line(parse_lex_result)
      result = line_results[line_index]
      if result
        prev_opens, next_opens, min_depth = result
      else
        # When last line is empty
        prev_opens = next_opens = line_results.last[1]
        min_depth = next_opens.size
      end

      # To correctly indent line like `end.map do`, we use shortest open tokens on each line for indent calculation.
      # Shortest open tokens can be calculated by `opens.take(min_depth)`
      indent = 2 * calc_indent_level(prev_opens.take(min_depth))

      preserve_indent = lines[line_index - (is_newline ? 1 : 0)][/^ */].size

      prev_open_elem = prev_opens.last
      next_open_elem = next_opens.last

      # Calculates base indent for pasted code on the line where prev_open_elem is located
      # irb(main):001:1*   if a # base_indent is 2, indent calculated from nestings is 0
      # irb(main):002:1*         if b # base_indent is 6, indent calculated from nestings is 2
      # irb(main):003:0>           c # base_indent is 6, indent calculated from nestings is 4
      if prev_open_elem
        base_indent = [0, indent_difference(lines, line_results, prev_open_elem.pos[0] - 1)].max
      else
        base_indent = 0
      end

      if free_indent_nesting_element?(prev_open_elem)
        if is_newline && prev_open_elem.pos[0] == line_index
          # First newline inside free-indent token
          base_indent + indent
        else
          # Accept any number of indent inside free-indent token
          preserve_indent
        end
      elsif prev_open_elem&.event == :on_embdoc_beg || next_open_elem&.event == :on_embdoc_beg
        if prev_open_elem&.event == next_open_elem&.event
          # Accept any number of indent inside embdoc content
          preserve_indent
        else
          # =begin or =end
          0
        end
      elsif prev_open_elem&.event == :on_heredoc_beg
        tok = prev_open_elem.tok
        if prev_opens.size <= next_opens.size
          if is_newline && lines[line_index].empty? && line_results[line_index - 1][0].last != next_open_elem
            # First line in heredoc
            tok.match?(/^<<[-~]/) ? base_indent + indent : indent
          elsif tok.match?(/^<<~/)
            # Accept extra indent spaces inside `<<~` heredoc
            [base_indent + indent, preserve_indent].max
          else
            # Accept any number of indent inside other heredoc
            preserve_indent
          end
        else
          # Heredoc close
          prev_line_indent_level = calc_indent_level(prev_opens)
          tok.match?(/^<<[~-]/) ? base_indent + 2 * (prev_line_indent_level - 1) : 0
        end
      else
        base_indent + indent
      end
    end

    def ltype_from_open_nestings(opens)
      start_nesting = opens.reverse_each.find do |elem|
        LTYPE_TOKENS.include?(elem.event)
      end
      return nil unless start_nesting

      case start_nesting&.event
      when :on_tstring_beg
        case start_nesting&.tok
        when ?"      then ?"
        when /^%.$/  then ?"
        when /^%Q.$/ then ?"
        when ?'      then ?'
        when /^%q.$/ then ?'
        end
      when :on_regexp_beg   then ?/
      when :on_symbeg       then ?:
      when :on_backtick     then ?`
      when :on_qwords_beg   then ?]
      when :on_words_beg    then ?]
      when :on_qsymbols_beg then ?]
      when :on_symbols_beg  then ?]
      when :on_heredoc_beg
        start_nesting&.tok =~ /<<[-~]?(['"`])\w+\1/
        $1 || ?"
      else
        nil
      end
    end

    # Check if <tt>code.lines[...-1]</tt> is terminated and can be evaluated immediately.
    # Returns the last line string if terminated, otherwise false.
    # Terminated means previous lines(<tt>code.lines[...-1]</tt>) is syntax valid and
    # previous lines and the last line are syntactically separated.
    # Terminated example
    #   foo(
    #   bar)
    #   baz.
    # Unterminated example: previous lines are syntax invalid
    #   foo(
    #   bar).
    #   baz
    # Unterminated example: previous lines are connected to the last line
    #   foo(
    #   bar)
    #   .baz
    def check_termination_in_prev_line(code, local_variables:)
      lines = code.lines
      return false if lines.size < 2

      prev_line_result = Prism.parse(lines[...-1].join, scopes: [local_variables])
      return false unless prev_line_result.success?

      prev_nodes = prev_line_result.value.statements.body
      whole_nodes = Prism.parse(code, scopes: [local_variables]).value.statements.body

      return false if whole_nodes.size < prev_nodes.size
      return false unless prev_nodes.zip(whole_nodes).all? do |a, b|
        a.location == b.location
      end

      # If the last line only contain comments, treat it as not connected to handle this case:
      #   receiver
      #   # comment
      #   .method
      return false if lines.last.match?(/\A\s*#/)

      lines.last
    end
  end
  # :startdoc:
end

RubyLex = IRB::RubyLex
Object.deprecate_constant(:RubyLex)
