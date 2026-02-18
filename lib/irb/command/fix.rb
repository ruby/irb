# frozen_string_literal: true

# Fix command: reruns the previous command with corrected spelling when a
# "Did you mean?" error occurred. Works with exceptions that have #corrections
# (e.g. from the did_you_mean gem).
#
# See: https://github.com/ruby/did_you_mean/issues/179

module IRB
  module Command
    class Fix < Base
      MAX_EDIT_DISTANCE = 2

      category "did_you_mean"
      description "Rerun the previous command with corrected spelling from Did you mean?"

      def execute(_arg)
        code = LastError.last_code
        exception = LastError.last_exception

        if code.nil? || exception.nil?
          puts "No previous error with Did you mean? suggestions. Try making a typo first, e.g. 1.zeor?"
          return
        end

        unless correctable?(exception)
          puts "Last error is not correctable. The fix command only works with NoMethodError, NameError, KeyError, etc."
          return
        end

        wrong_str, correction = extract_correction(exception)
        return unless correction

        corrected_code = apply_correction(code, wrong_str, correction)
        return unless corrected_code

        puts "Rerunning with: #{corrected_code}"
        eval_path = @irb_context.instance_variable_get(:@eval_path) || "(irb)"
        result = @irb_context.workspace.evaluate(corrected_code, eval_path, LastError.last_line_no)
        @irb_context.set_last_value(result)
        @irb_context.irb.output_value if @irb_context.echo?
        LastError.clear
      end

      class << self
        def fixable?
          return false if LastError.last_code.nil? || LastError.last_exception.nil?
          cmd = allocate
          cmd.instance_variable_set(:@irb_context, nil)
          return false unless cmd.send(:correctable?, LastError.last_exception)
          wrong_str, correction = cmd.send(:extract_correction, LastError.last_exception)
          return false if correction.nil?
          !cmd.send(:apply_correction, LastError.last_code, wrong_str, correction).nil?
        end
      end

      private

      def correctable?(exception)
        exception.respond_to?(:corrections) && exception.is_a?(Exception)
      end

      def extract_correction(exception)
        corrections = exception.corrections
        return [nil, nil] if corrections.nil? || corrections.empty?

        wrong_str = wrong_string_from(exception)
        return [nil, nil] if wrong_str.nil? || wrong_str.to_s.empty?

        # Use did_you_mean's Levenshtein when available
        filtered = if defined?(DidYouMean::Levenshtein)
          corrections.select do |c|
            correction_str = c.is_a?(Array) ? c.first.to_s : c.to_s
            DidYouMean::Levenshtein.distance(normalize(wrong_str), normalize(correction_str)) <= MAX_EDIT_DISTANCE
          end
        else
          corrections
        end

        return [nil, nil] unless filtered.size == 1

        correction = filtered.first
        correction_str = correction.is_a?(Array) ? correction.first : correction
        [wrong_str.to_s, correction_str]
      end

      def wrong_string_from(exception)
        case exception
        when NoMethodError
          exception.name.to_s
        when NameError
          exception.name.to_s
        when KeyError
          exception.key.to_s
        when defined?(NoMatchingPatternKeyError) && NoMatchingPatternKeyError
          exception.key.to_s
        when LoadError
          exception.message[/cannot load such file -- (.+)/, 1]
        else
          nil
        end
      end

      def normalize(str)
        str.to_s.downcase
      end

      def apply_correction(code, wrong_str, correction_str)
        correction_display = correction_str.to_s

        patterns = [
          [wrong_str, correction_display],
          [":#{wrong_str}", ":#{correction_display}"],
          ["\"#{wrong_str}\"", "\"#{correction_display}\""],
          ["'#{wrong_str}'", "'#{correction_display}'"],
        ]

        patterns.each do |wrong_pattern, correct_pattern|
          escaped = Regexp.escape(wrong_pattern)
          new_code = code.sub(/#{escaped}/, correct_pattern)
          return new_code if new_code != code
        end

        nil
      end
    end

    # Stores the last failed code and exception for the fix command
    module LastError
      @last_code = nil
      @last_exception = nil
      @last_line_no = 1

      class << self
        attr_accessor :last_code, :last_exception, :last_line_no

        def store(code, exception, line_no)
          self.last_code = code
          self.last_exception = exception
          self.last_line_no = line_no
        end

        def clear
          self.last_code = nil
          self.last_exception = nil
          self.last_line_no = 1
        end
      end
    end
  end
end
