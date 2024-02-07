# frozen_string_literal: true

require_relative "ruby-lex"

module IRB
  class SourceFinder
    Source = Struct.new(
      :file,         # @param [String]  - file name
      :first_line,   # @param [Integer] - first line (unless binary file)
      :last_line,    # @param [Integer] - last line (if available from file)
      :content,      # @param [String]  - source (if available from file or AST)
      :file_content, # @param [String]  - whole file content
      keyword_init: true,
    )
    private_constant :Source

    def initialize(irb_context)
      @irb_context = irb_context
    end

    def find_source(signature, super_level = 0)
      context_binding = @irb_context.workspace.binding
      case signature
      when /\A(::)?[A-Z]\w*(::[A-Z]\w*)*\z/ # Const::Name
        eval(signature, context_binding) # trigger autoload
        base = context_binding.receiver.yield_self { |r| r.is_a?(Module) ? r : Object }
        file, line = base.const_source_location(signature)
      when /\A(?<owner>[A-Z]\w*(::[A-Z]\w*)*)#(?<method>[^ :.]+)\z/ # Class#method
        owner = eval(Regexp.last_match[:owner], context_binding)
        method = Regexp.last_match[:method]
        return unless owner.respond_to?(:instance_method)
        method = method_target(owner, super_level, method, "owner")
        file, line = method&.source_location
      when /\A((?<receiver>.+)(\.|::))?(?<method>[^ :.]+)\z/ # method, receiver.method, receiver::method
        receiver = eval(Regexp.last_match[:receiver] || 'self', context_binding)
        method = Regexp.last_match[:method]
        return unless receiver.respond_to?(method, true)
        method = method_target(receiver, super_level, method, "receiver")
        file, line = method&.source_location
      end
      return unless file && line

      if File.exist?(file)
        if line.zero?
          # If the line is zero, it means that the target's source is probably in a binary file.
          Source.new(file: file)
        else
          code = File.read(file)
          file_lines = code.lines
          last_line = find_end(file_lines, line)
          content = file_lines[line..last_line].join
          Source.new(file: file, first_line: line, last_line: last_line, content: content, file_content: code)
        end
      elsif method
        # Method defined with eval, probably in IRB session
        source = RubyVM::AbstractSyntaxTree.of(method)&.source rescue nil
        Source.new(file: file, first_line: line, content: source)
      end
    end

    private

    def find_end(file_lines, first_line)
      lex = RubyLex.new
      lines = file_lines[(first_line - 1)..-1]
      tokens = RubyLex.ripper_lex_without_warning(lines.join)
      prev_tokens = []

      # chunk with line number
      tokens.chunk { |tok| tok.pos[0] }.each do |lnum, chunk|
        code = lines[0..lnum].join
        prev_tokens.concat chunk
        continue = lex.should_continue?(prev_tokens)
        syntax = lex.check_code_syntax(code, local_variables: [])
        if !continue && syntax == :valid
          return first_line + lnum
        end
      end
      first_line
    end

    def method_target(owner_receiver, super_level, method, type)
      case type
      when "owner"
        target_method = owner_receiver.instance_method(method)
      when "receiver"
        target_method = owner_receiver.method(method)
      end
      super_level.times do |s|
        target_method = target_method.super_method if target_method
      end
      target_method
    rescue NameError
      nil
    end
  end
end
