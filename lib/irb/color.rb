# frozen_string_literal: true
require 'reline'
require 'prism'
require_relative 'ruby-lex'

module IRB # :nodoc:
  module Color
    CLEAR     = 0
    BOLD      = 1
    UNDERLINE = 4
    REVERSE   = 7
    BLACK     = 30
    RED       = 31
    GREEN     = 32
    YELLOW    = 33
    BLUE      = 34
    MAGENTA   = 35
    CYAN      = 36
    WHITE     = 37

    TOKEN_FACES = {
      KEYWORD_NIL:                 :pseudo_variable,
      KEYWORD_SELF:                :pseudo_variable,
      KEYWORD_TRUE:                :pseudo_variable,
      KEYWORD_FALSE:               :pseudo_variable,
      KEYWORD___FILE__:            :pseudo_variable,
      KEYWORD___LINE__:            :pseudo_variable,
      KEYWORD___ENCODING__:        :pseudo_variable,
      CHARACTER_LITERAL:           :number,
      BACK_REFERENCE:              :global_variable,
      BACKTICK:                    :string_edge,
      COMMENT:                     :comment,
      EMBDOC_BEGIN:                :comment,
      EMBDOC_LINE:                 :comment,
      EMBDOC_END:                  :comment,
      CONSTANT:                    :constant,
      EMBEXPR_BEGIN:               :string_body,
      EMBEXPR_END:                 :string_body,
      EMBVAR:                      :string_body,
      FLOAT:                       :float,
      GLOBAL_VARIABLE:             :global_variable,
      HEREDOC_START:               :string_body,
      HEREDOC_END:                 :string_body,
      FLOAT_IMAGINARY:             :number,
      INTEGER_IMAGINARY:           :number,
      FLOAT_RATIONAL_IMAGINARY:    :number,
      INTEGER_RATIONAL_IMAGINARY:  :number,
      INTEGER:                     :number,
      INTEGER_RATIONAL:            :number,
      FLOAT_RATIONAL:              :number,
      KEYWORD_END:                 :keyword,
      KEYWORD_CLASS:               :keyword,
      KEYWORD_MODULE:              :keyword,
      KEYWORD_IF:                  :keyword,
      KEYWORD_IF_MODIFIER:         :keyword,
      KEYWORD_UNLESS_MODIFIER:     :keyword,
      KEYWORD_WHILE_MODIFIER:      :keyword,
      KEYWORD_UNTIL_MODIFIER:      :keyword,
      KEYWORD_RESCUE_MODIFIER:     :keyword,
      KEYWORD_THEN:                :keyword,
      KEYWORD_UNLESS:              :keyword,
      KEYWORD_ELSE:                :keyword,
      KEYWORD_ELSIF:               :keyword,
      KEYWORD_WHILE:               :keyword,
      KEYWORD_UNTIL:               :keyword,
      KEYWORD_CASE:                :keyword,
      KEYWORD_WHEN:                :keyword,
      KEYWORD_IN:                  :keyword,
      KEYWORD_DEF:                 :keyword,
      KEYWORD_DO:                  :keyword,
      KEYWORD_DO_LOOP:             :keyword,
      KEYWORD_FOR:                 :keyword,
      KEYWORD_BEGIN:               :keyword,
      KEYWORD_RESCUE:              :keyword,
      KEYWORD_ENSURE:              :keyword,
      KEYWORD_ALIAS:               :keyword,
      KEYWORD_UNDEF:               :keyword,
      KEYWORD_BEGIN_UPCASE:        :keyword,
      KEYWORD_END_UPCASE:          :keyword,
      KEYWORD_YIELD:               :keyword,
      KEYWORD_REDO:                :keyword,
      KEYWORD_RETRY:               :keyword,
      KEYWORD_NEXT:                :keyword,
      KEYWORD_BREAK:               :keyword,
      KEYWORD_SUPER:               :keyword,
      KEYWORD_RETURN:              :keyword,
      KEYWORD_DEFINED:             :keyword,
      KEYWORD_NOT:                 :keyword,
      KEYWORD_AND:                 :keyword,
      KEYWORD_OR:                  :keyword,
      LABEL:                       :label,
      LABEL_END:                   :string_edge,
      NUMBERED_REFERENCE:          :global_variable,
      PERCENT_UPPER_W:             :string_edge,
      PERCENT_LOWER_W:             :string_edge,
      PERCENT_LOWER_X:             :string_edge,
      REGEXP_BEGIN:                :string_edge,
      REGEXP_END:                  :string_edge,
      STRING_BEGIN:                :string_edge,
      STRING_CONTENT:              :string_body,
      STRING_END:                  :string_edge,
      __END__:                     :keyword,
      # tokens from syntax tree traversal
      method_name:                 :method_name,
      message_name:                :message_name,
      symbol:                      :symbol,
      # special colorization
      error:                       :error,
    }

    TOKEN_SEQS = {}
    CLEAR_SEQ = "\e[#{CLEAR}m"
    OPERATORS = %i(!= !~ =~ == === <=> > >= < <= & | ^ >> << - + % / * ** -@ +@ ~ ! [] []=)
    private_constant :TOKEN_FACES, :TOKEN_SEQS, :CLEAR_SEQ, :OPERATORS

    class << self
      def init
        face_conf = Reline::Face[:syntax_highlighting]
        face_seqs = {}
        face_conf.definition.each do |key, val|
          face_seqs[key] = normalize_sgr(val[:escape_sequence])
        end
        TOKEN_SEQS.clear
        TOKEN_FACES.each do |key, val|
          TOKEN_SEQS[key] = face_seqs[val]
        end
      end

      def colorable?
        supported = $stdout.tty? && (/mswin|mingw/.match?(RUBY_PLATFORM) || (ENV.key?('TERM') && ENV['TERM'] != 'dumb'))

        # because ruby/debug also uses irb's color module selectively,
        # irb won't be activated in that case.
        if IRB.respond_to?(:conf)
          supported && !!IRB.conf.fetch(:USE_COLORIZE, true)
        else
          supported
        end
      end

      def inspect_colorable?(obj, seen: {}.compare_by_identity)
        case obj
        when String, Symbol, Regexp, Integer, Float, FalseClass, TrueClass, NilClass
          true
        when Hash
          without_circular_ref(obj, seen: seen) do
            obj.all? { |k, v| inspect_colorable?(k, seen: seen) && inspect_colorable?(v, seen: seen) }
          end
        when Array
          without_circular_ref(obj, seen: seen) do
            obj.all? { |o| inspect_colorable?(o, seen: seen) }
          end
        when Range
          inspect_colorable?(obj.begin, seen: seen) && inspect_colorable?(obj.end, seen: seen)
        when Module
          !obj.name.nil?
        else
          false
        end
      end

      def clear(colorable: colorable?)
        colorable ? CLEAR_SEQ : ''
      end

      def colorize(text, seq, colorable: colorable?)
        return text unless colorable
        seq = seq.map { |s| "\e[#{const_get(s)}m" }.join('')
        "#{seq}#{text}#{CLEAR_SEQ}"
      end

      # If `complete` is false (code is incomplete), this does not warn compile_error.
      # This option is needed to avoid warning a user when the compile_error is happening
      # because the input is not wrong but just incomplete.
      def colorize_code(code, complete: true, ignore_error: false, colorable: colorable?, local_variables: [])
        return code unless colorable

        result = Prism.parse_lex(code, scopes: [local_variables])

        # IRB::ColorPrinter skips colorizing syntax invalid fragments
        return Reline::Unicode.escape_for_print(code) if ignore_error && !result.success?

        prism_node, prism_tokens = result.value
        errors = result.errors

        unless complete
          errors = filter_incomplete_code_errors(errors, prism_tokens)
        end

        visitor = ColorizeVisitor.new
        prism_node.accept(visitor)

        error_tokens = errors.map { |e| [e.location.start_line, e.location.start_column, 0, e.location.end_line, e.location.end_column, :error, e.location.slice] }
        error_tokens.reject! { |t| t.last.match?(/\A\s*\z/) }
        tokens = prism_tokens.map { |t,| [t.location.start_line, t.location.start_column, 2, t.location.end_line, t.location.end_column, t.type, t.value] }
        tokens.pop if tokens.last&.[](5) == :EOF

        colored = +''
        line_index = 0
        col = 0
        lines = code.lines
        flush = -> next_line_index, next_col {
          return if next_line_index == line_index && next_col == col
          (line_index...[next_line_index, lines.size].min).each do |ln|
            colored << Reline::Unicode.escape_for_print(lines[line_index].byteslice(col..))
            line_index = ln + 1
            col = 0
          end
          unless col == next_col
            colored << Reline::Unicode.escape_for_print(lines[next_line_index].byteslice(col..next_col - 1))
          end
        }

        (visitor.tokens + tokens + error_tokens).sort.each do |start_line, start_column, _priority, end_line, end_column, type, value|
          next if start_line - 1 < line_index || (start_line - 1 == line_index && start_column < col)

          flush.call(start_line - 1, start_column)
          if type == :__END__
            color = TOKEN_SEQS[type]
            end_line = start_line
            value = '__END__'
            end_column = start_column + 7
          else
            color = TOKEN_SEQS[type]
          end
          if color
            value.split(/(\n)/).each do |s|
              colored << (s == "\n" ? s : "#{color}#{Reline::Unicode.escape_for_print(s)}#{CLEAR_SEQ}")
            end
          else
            colored << value
          end
          line_index = end_line - 1
          col = end_column
        end
        flush.call lines.size, 0
        colored
      end

      class ColorizeVisitor < Prism::Visitor
        attr_reader :tokens
        def initialize
          @tokens = []
        end

        def dispatch(location, type)
          if location
            @tokens << [location.start_line, location.start_column, 1, location.end_line, location.end_column, type, location.slice]
          end
        end

        def visit_array_node(node)
          if node.opening&.match?(/\A%[iI]/)
            dispatch node.opening_loc, :symbol
            dispatch node.closing_loc, :symbol
          end
          super
        end

        def visit_def_node(node)
          dispatch node.name_loc, :method_name
          super
        end

        def visit_alias_method_node(node)
          dispatch_alias_method_name node.new_name
          dispatch_alias_method_name node.old_name
          super
        end

        def visit_call_node(node)
          if node.call_operator_loc.nil? && OPERATORS.include?(node.name)
            # Operators should not be colored as method call
          elsif (node.call_operator_loc.nil? || node.call_operator_loc.slice == "::") &&
              /\A\p{Upper}/.match?(node.name)
            # Constant-like methods should not be colored as method call
          else
            dispatch node.message_loc, :message_name
          end
          super
        end

        def visit_call_operator_write_node(node)
          dispatch node.message_loc, :message_name
          super
        end
        alias visit_call_and_write_node visit_call_operator_write_node
        alias visit_call_or_write_node visit_call_operator_write_node

        def visit_interpolated_symbol_node(node)
          dispatch node.opening_loc, :symbol
          node.parts.each do |part|
            case part
            when Prism::StringNode
              dispatch part.content_loc, :symbol
            when Prism::EmbeddedStatementsNode
              dispatch part.opening_loc, :symbol
              dispatch part.closing_loc, :symbol
            when Prism::EmbeddedVariableNode
              dispatch part.operator_loc, :symbol
            end
          end
          dispatch node.closing_loc, :symbol
          super
        end

        def visit_symbol_node(node)
          if (node.opening_loc.nil? && node.closing == ':') || node.closing&.match?(/\A['"]:\z/)
            # Colorize { symbol: 1 } and { 'symbol': 1 } as label
            dispatch node.location, :LABEL
          else
            dispatch node.opening_loc, :symbol
            dispatch node.value_loc, :symbol
            dispatch node.closing_loc, :symbol
          end
        end

        private

        def dispatch_alias_method_name(node)
          if node.type == :symbol_node && node.opening_loc.nil?
            dispatch node.value_loc, :method_name
          end
        end
      end

      private

      FILTERED_ERROR_TYPES = [
        :class_name, :module_name, # `class`, `class owner_module`
        :write_target_unexpected, # `a, b`
        :parameter_wild_loose_comma, # `def f(a,`
        :argument_no_forwarding_star, # `[*`
        :argument_no_forwarding_star_star, # `f(**`
        :argument_no_forwarding_ampersand, # `f(&`
        :def_endless, # `def f =`
        :embdoc_term, # `=begin`
      ]

      # Normalize SGR sequences for existing test cases
      def normalize_sgr(seq)
        s = seq.sub(/\A\e\[0m/, "")
        return s if s.match?(/\e\[(38|48|58);/) # Do not normalize extended colors
        s.gsub(/\e\[([0-9;]+)m/) {
          $1.split(/;/).map { |i| "\e[#{i}m" }.join
        }
      end

      # Filter out syntax errors that are likely to be caused by incomplete code, to avoid showing misleading error highlights to users.
      def filter_incomplete_code_errors(errors, tokens)
        last_non_comment_space_token, = tokens.reverse_each.find do |t,|
          t.type != :COMMENT && t.type != :EOF && t.type != :IGNORED_NEWLINE && t.type != :NEWLINE
        end
        last_offset = last_non_comment_space_token ? last_non_comment_space_token.location.end_offset : 0
        errors.reject do |error|
          error.message.match?(/\Aexpected a|unexpected end-of-input|unterminated/) ||
          (error.location.end_offset == last_offset && FILTERED_ERROR_TYPES.include?(error.type))
        end
      end

      def without_circular_ref(obj, seen:, &block)
        return false if seen.key?(obj)
        seen[obj] = true
        block.call
      ensure
        seen.delete(obj)
      end
    end
  end
end

# Following pry's colors where possible
Reline::Face.config(:syntax_highlighting) do |conf|
  conf.define :pseudo_variable,  foreground: :cyan,     style: :bold
  conf.define :global_variable,  foreground: :green,    style: :bold
  conf.define :constant,         foreground: :blue,     style: [:bold, :underlined]
  conf.define :comment,          foreground: :blue,     style: :bold
  conf.define :string_edge,      foreground: :red,      style: :bold
  conf.define :string_body,      foreground: :red
  conf.define :symbol,           foreground: :yellow
  conf.define :number,           foreground: :blue,     style: :bold
  conf.define :float,            foreground: :magenta,  style: :bold
  conf.define :keyword,          foreground: :green
  conf.define :label,            foreground: :magenta
  conf.define :method_name,      foreground: :cyan,     style: :bold
  conf.define :message_name,     foreground: :cyan
  conf.define :error,            foreground: :red,      style: :negative
end

IRB::Color.init
