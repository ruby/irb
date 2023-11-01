# frozen_string_literal: true

require_relative "ruby-lex"

module IRB
  class SourceFinder
    Source = Struct.new(
      :file,       # @param [String] - file name
      :first_line, # @param [String] - first line
      :last_line,  # @param [String] - last line
      keyword_init: true,
    )
    private_constant :Source

    def initialize(binding)
      @binding = binding
    end

    def find_source(signature)
      case signature
      when /\A[A-Z]\w*(::[A-Z]\w*)*\z/ # Const::Name
        eval(signature, @binding) # trigger autoload
        base = @binding.receiver.yield_self { |r| r.is_a?(Module) ? r : Object }
        file, line = base.const_source_location(signature)
      when /\A(?<owner>[A-Z]\w*(::[A-Z]\w*)*)#(?<method>[^ :.]+)\z/ # Class#method
        owner = eval(Regexp.last_match[:owner], @binding)
        method = Regexp.last_match[:method]
        if owner.respond_to?(:instance_method)
          methods = owner.instance_methods + owner.private_instance_methods
          file, line = owner.instance_method(method).source_location if methods.include?(method.to_sym)
        end
      when /\A((?<receiver>.+)(\.|::))?(?<method>[^ :.]+)\z/ # method, receiver.method, receiver::method
        receiver = eval(Regexp.last_match[:receiver] || 'self', @binding)
        method = Regexp.last_match[:method]
        file, line = receiver.method(method).source_location if receiver.respond_to?(method, true)
      end
      if file && line && File.exist?(file)
        code = File.read(file)
        Source.new(file: file, first_line: line, last_line: find_end(code, line))
      end
    end

    private

    def find_end(code, first_line)
      tokens = RubyLex.ripper_lex_without_warning(code)
      line_results = NestingParser.parse_by_line(tokens)
      _tokens, prev_opens, next_opens, _min_depth = line_results[first_line - 1]
      in_heredoc = prev_opens.last&.event == :on_heredoc_beg
      # New open tokens in first_line. Need to find end_line that closes all of them.
      tokens_to_be_closed = next_opens - prev_opens
      # If the content is inside heredoc, find the end of the heredoc.
      tokens_to_be_closed << next_opens.last if in_heredoc

      line_tokens = line_results.map { |_tokens, prev, _next, _min_depth| prev }
      end_line = (first_line...line_tokens.size).find do |index|
        (line_tokens[index] & tokens_to_be_closed).empty?
      end
      return line_tokens.size unless end_line
      in_heredoc ? end_line - 1 : end_line
    end
  end
end
