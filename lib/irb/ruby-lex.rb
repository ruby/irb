# frozen_string_literal: false
#
#   irb/ruby-lex.rb - ruby lexcal analyzer
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

require "ripper"
require "jruby" if RUBY_ENGINE == "jruby"
require_relative "nesting_parser"

# :stopdoc:
class RubyLex

  class TerminateLineInput < StandardError
    def initialize
      super("Terminate Line Input")
    end
  end

  def initialize(context)
    @context = context
    @line_no = 1
    @prompt = nil
  end

  def self.compile_with_errors_suppressed(code, line_no: 1)
    begin
      result = yield code, line_no
    rescue ArgumentError
      # Ruby can issue an error for the code if there is an
      # incomplete magic comment for encoding in it. Force an
      # expression with a new line before the code in this
      # case to prevent magic comment handling.  To make sure
      # line numbers in the lexed code remain the same,
      # decrease the line number by one.
      code = ";\n#{code}"
      line_no -= 1
      result = yield code, line_no
    end
    result
  end

  def single_line_command?(code)
    command = code.split(/\s/, 2).first
    @context.symbol_alias?(command) || @context.transform_args?(command)
  end

  # io functions
  def set_input(&block)
    @input = block
  end

  def configure_io(io)
    @io = io
    if @io.respond_to?(:check_termination)
      @io.check_termination do |code|
        if Reline::IOGate.in_pasting?
          rest = check_termination_in_prev_line(code)
          if rest
            Reline.delete_text
            rest.bytes.reverse_each do |c|
              Reline.ungetc(c)
            end
            true
          else
            false
          end
        else
          # Accept any single-line input for symbol aliases or commands that transform args
          next true if single_line_command?(code)

          check_target_code, tokens, opens = check_code_state(code)
          continue = process_continue(tokens)
          opens.empty? && !continue && !check_code_block(check_target_code, tokens)
        end
      end
    end
    if @io.respond_to?(:dynamic_prompt)
      @io.dynamic_prompt do |lines|
        lines << '' if lines.empty?
        tokens = self.class.ripper_lex_without_warning(lines.map{ |l| l + "\n" }.join, context: @context)
        line_results = IRB::NestingParser.parse_by_line(tokens)
        tokens_until_line = []
        line_results.map.with_index do |(line_tokens, _prev_opens, next_opens), line_num_offset|
          line_tokens.each do |token, _s|
            tokens_until_line << token if token != tokens_until_line.last
          end
          continue = process_continue(tokens_until_line)
          prompt(next_opens, continue, line_num_offset)
        end
      end
    end

    if @io.respond_to?(:auto_indent) and @context.auto_indent_mode
      @io.auto_indent do |lines, line_index, byte_pointer, is_newline|
        if is_newline
          tokens = self.class.ripper_lex_without_warning(lines[0..line_index].join("\n"), context: @context)
          process_indent_level(tokens, lines)
        else
          code = line_index.zero? ? '' : lines[0..(line_index - 1)].map{ |l| l + "\n" }.join
          last_line = lines[line_index]&.byteslice(0, byte_pointer)
          code += last_line if last_line
          tokens = self.class.ripper_lex_without_warning(code, context: @context)
          check_corresponding_token_depth(tokens, lines, line_index)
        end
      end
    end
  end

  def set_prompt(&block)
    @prompt = block
  end

  ERROR_TOKENS = [
    :on_parse_error,
    :compile_error,
    :on_assign_error,
    :on_alias_error,
    :on_class_name_error,
    :on_param_error
  ]

  def self.generate_local_variables_assign_code(local_variables)
    "#{local_variables.join('=')}=nil;" unless local_variables.empty?
  end

  def self.ripper_lex_without_warning(code, context: nil)
    verbose, $VERBOSE = $VERBOSE, nil
    lvars_code = generate_local_variables_assign_code(context&.local_variables || [])
    if lvars_code
      code = "#{lvars_code}\n#{code}"
      line_no = 0
    else
      line_no = 1
    end

    compile_with_errors_suppressed(code, line_no: line_no) do |inner_code, line_no|
      lexer = Ripper::Lexer.new(inner_code, '-', line_no)
      lexer.scan.each_with_object([]) do |t, tokens|
        next if t.pos.first == 0
        prev_tk = tokens.last
        position_overlapped = prev_tk && t.pos[0] == prev_tk.pos[0] && t.pos[1] < prev_tk.pos[1] + prev_tk.tok.bytesize
        if position_overlapped
          tokens[-1] = t if ERROR_TOKENS.include?(prev_tk.event) && !ERROR_TOKENS.include?(t.event)
        else
          tokens << t
        end
      end
    end
  ensure
    $VERBOSE = verbose
  end

  def prompt(opens, continue, line_num_offset)
    ltype = ltype_from_open_tokens(opens)
    _indent, nesting_level = calc_nesting_depth(opens)
    @prompt&.call(ltype, nesting_level, opens.any? || continue, @line_no + line_num_offset)
  end

  def check_code_state(code)
    check_target_code = code.gsub(/\s*\z/, '').concat("\n")
    tokens = self.class.ripper_lex_without_warning(check_target_code, context: @context)
    opens = IRB::NestingParser.open_tokens(tokens)
    [check_target_code, tokens, opens]
  end

  def save_prompt_to_context_io(opens, continue, line_num_offset)
    # Implicitly saves prompt string to `@context.io.prompt`. This will be used in the next `@input.call`.
    prompt(opens, continue, line_num_offset)
  end

  def readmultiline
    save_prompt_to_context_io([], false, 0)

    # multiline
    return @input.call if @io.respond_to?(:check_termination)

    # nomultiline
    code = ''
    line_offset = 0
    loop do
      line = @input.call
      unless line
        return code.empty? ? nil : code
      end

      code << line
      # Accept any single-line input for symbol aliases or commands that transform args
      return code if single_line_command?(code)

      check_target_code, tokens, opens = check_code_state(code)
      continue = process_continue(tokens)
      return code if opens.empty? && !continue && !check_code_block(check_target_code, tokens)

      line_offset += 1
      save_prompt_to_context_io(opens, continue, line_offset)
    end
  end

  def each_top_level_statement
    loop do
      code = readmultiline
      break unless code

      if code != "\n"
        code.force_encoding(@io.encoding)
        yield code, @line_no
      end
      @line_no += code.count("\n")
    rescue TerminateLineInput
    end
  end

  def process_continue(tokens)
    # last token is always newline
    if tokens.size >= 2 and tokens[-2].event == :on_regexp_end
      # end of regexp literal
      return false
    elsif tokens.size >= 2 and tokens[-2].event == :on_semicolon
      return false
    elsif tokens.size >= 2 and tokens[-2].event == :on_kw and ['begin', 'else', 'ensure'].include?(tokens[-2].tok)
      return false
    elsif !tokens.empty? and tokens.last.tok == "\\\n"
      return true
    elsif tokens.size >= 1 and tokens[-1].event == :on_heredoc_end # "EOH\n"
      return false
    elsif tokens.size >= 2 and tokens[-2].state.anybits?(Ripper::EXPR_BEG | Ripper::EXPR_FNAME) and tokens[-2].tok !~ /\A\.\.\.?\z/
      # end of literal except for regexp
      # endless range at end of line is not a continue
      return true
    end
    false
  end

  def check_code_block(code, tokens)
    return true if tokens.empty?

    begin # check if parser error are available
      verbose, $VERBOSE = $VERBOSE, nil
      case RUBY_ENGINE
      when 'ruby'
        self.class.compile_with_errors_suppressed(code) do |inner_code, line_no|
          RubyVM::InstructionSequence.compile(inner_code, nil, nil, line_no)
        end
      when 'jruby'
        JRuby.compile_ir(code)
      else
        catch(:valid) do
          eval("BEGIN { throw :valid, true }\n#{code}")
          false
        end
      end
    rescue EncodingError
      # This is for a hash with invalid encoding symbol, {"\xAE": 1}
    rescue SyntaxError => e
      case e.message
      when /unterminated (?:string|regexp) meets end of file/
        # "unterminated regexp meets end of file"
        #
        #   example:
        #     /
        #
        # "unterminated string meets end of file"
        #
        #   example:
        #     '
        return true
      when /syntax error, unexpected end-of-input/
        # "syntax error, unexpected end-of-input, expecting keyword_end"
        #
        #   example:
        #     if true
        #       hoge
        #       if false
        #         fuga
        #       end
        return true
      when /syntax error, unexpected keyword_end/
        # "syntax error, unexpected keyword_end"
        #
        #   example:
        #     if (
        #     end
        #
        #   example:
        #     end
        return false
      when /syntax error, unexpected '\.'/
        # "syntax error, unexpected '.'"
        #
        #   example:
        #     .
        return false
      when /unexpected tREGEXP_BEG/
        # "syntax error, unexpected tREGEXP_BEG, expecting keyword_do or '{' or '('"
        #
        #   example:
        #     method / f /
        return false
      end
    ensure
      $VERBOSE = verbose
    end

    last_lex_state = tokens.last.state

    if last_lex_state.allbits?(Ripper::EXPR_BEG)
      return false
    elsif last_lex_state.allbits?(Ripper::EXPR_DOT)
      return true
    elsif last_lex_state.allbits?(Ripper::EXPR_CLASS)
      return true
    elsif last_lex_state.allbits?(Ripper::EXPR_FNAME)
      return true
    elsif last_lex_state.allbits?(Ripper::EXPR_VALUE)
      return true
    elsif last_lex_state.allbits?(Ripper::EXPR_ARG)
      return false
    end

    false
  end

  def calc_nesting_depth(opens)
    indent_level = 0
    nesting_level = 0
    opens.each do |t|
      case t.event
      when :on_heredoc_beg
        # TODO: indent heredoc
      when :on_tstring_beg, :on_regexp_beg, :on_symbeg
        # can be indented if t.tok starts with `%`
      when :on_words_beg, :on_qwords_beg, :on_symbols_beg, :on_qsymbols_beg, :on_embexpr_beg
        # can be indented but not indented in current implementation
      when :on_embdoc_beg
        indent_level = 0
      else
        nesting_level += 1
        indent_level += 1
      end
    end
    [indent_level, nesting_level]
  end

  def free_indent_token(opens, line_index)
    last_token = opens.last
    return unless last_token
    if last_token.event == :on_heredoc_beg && last_token.pos.first < line_index + 1
      # accept extra indent spaces inside heredoc
      last_token
    end
  end

  def process_indent_level(tokens, lines)
    opens = IRB::NestingParser.open_tokens(tokens)
    depth, _nesting = calc_nesting_depth(opens)
    indent = depth * 2
    line_index = lines.size - 2
    if free_indent_token(opens, line_index)
      return [indent, lines[line_index][/^ */].length].max
    end
    indent
  end

  def check_corresponding_token_depth(tokens, lines, line_index)
    line_results = IRB::NestingParser.parse_by_line(tokens)
    result = line_results[line_index]
    return unless result
    _tokens, prev_opens, opens, min_depth = result
    depth, = calc_nesting_depth(opens.take(min_depth))
    indent = depth * 2
    free_indent_tok = free_indent_token(opens, line_index)
    prev_line_free_indent_tok = free_indent_token(prev_opens, line_index - 1)
    if prev_line_free_indent_tok && prev_line_free_indent_tok != free_indent_tok
      return indent
    elsif free_indent_tok
      return lines[line_index][/^ */].length
    end
    prev_depth, = calc_nesting_depth(prev_opens)
    indent if depth < prev_depth
  end

  def ltype_from_open_tokens(opens)
    start_token = opens.reverse_each.find do |tok|
      %i[
        on_heredoc_beg on_tstring_beg on_symbeg on_regexp_beg
        on_symbols_beg on_qsymbols_beg
        on_words_beg on_qwords_beg
      ].include?(tok.event)
    end
    return nil unless start_token

    case start_token&.event
    when :on_tstring_beg
      case start_token&.tok
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
      start_token&.tok =~ /<<[-~]?(['"`])\w+\1/
      $1 || ?"
    else
      nil
    end
  end

  def check_termination_in_prev_line(code)
    tokens = self.class.ripper_lex_without_warning(code, context: @context)
    past_first_newline = false
    index = tokens.rindex do |t|
      # traverse first token before last line
      if past_first_newline
        if t.tok.include?("\n")
          true
        end
      elsif t.tok.include?("\n")
        past_first_newline = true
        false
      else
        false
      end
    end

    if index
      first_token = nil
      last_line_tokens = tokens[(index + 1)..(tokens.size - 1)]
      last_line_tokens.each do |t|
        unless [:on_sp, :on_ignored_sp, :on_comment].include?(t.event)
          first_token = t
          break
        end
      end

      if first_token && first_token.state != Ripper::EXPR_DOT
        tokens_without_last_line = tokens[0..index]
        code_without_last_line = tokens_without_last_line.map(&:tok).join
        opens_without_last_line = IRB::NestingParser.open_tokens(tokens_without_last_line)
        if opens_without_last_line.empty? && !process_continue(tokens_without_last_line) && !check_code_block(code_without_last_line, tokens_without_last_line)
          return last_line_tokens.map(&:tok).join
        end
      end
    end
    false
  end
end
# :startdoc:
