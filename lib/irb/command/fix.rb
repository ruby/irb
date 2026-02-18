# frozen_string_literal: true

# Fix command: reruns the previous command with corrected spelling when a
# "Did you mean?" error occurred. Works with exceptions that have #corrections
# (e.g. from the did_you_mean gem).
#
# See: https://github.com/ruby/did_you_mean/issues/179

module IRB
  module Command
    class Fix < Base
      # Maximum Levenshtein distance for accepting a correction (did_you_mean default).
      MAX_EDIT_DISTANCE = 2

      HINT = "Type `fix` to rerun with the correction."
      MSG_NO_PREVIOUS_ERROR = "No previous error with Did you mean? suggestions. Try making a typo first, e.g. 1.zeor?"
      MSG_NOT_CORRECTABLE = "Last error is not correctable. The fix command only works with NoMethodError, NameError, KeyError, etc."
      MSG_RERUNNING = "Rerunning with: %s"

      category "did_you_mean"
      description "Rerun the previous command with corrected spelling from Did you mean?"

      def execute(_arg)
        code = LastError.last_code
        exception = LastError.last_exception

        if code.nil? || exception.nil?
          puts MSG_NO_PREVIOUS_ERROR
          return
        end

        unless correctable?(exception)
          puts MSG_NOT_CORRECTABLE
          return
        end

        wrong_str, correction = extract_correction(exception)
        return unless correction

        corrected_code = apply_correction(code, wrong_str, correction)
        return unless corrected_code

        puts format(MSG_RERUNNING, corrected_code)
        eval_path = @irb_context.eval_path || "(irb)"
        result = @irb_context.workspace.evaluate(corrected_code, eval_path, LastError.last_line_no)
        @irb_context.set_last_value(result)
        @irb_context.irb.output_value if @irb_context.echo?
        LastError.clear
      end

      class << self
        def fixable?
          code = LastError.last_code
          exception = LastError.last_exception
          return false if code.nil? || exception.nil?
          return false unless fix_correctable?(exception)
          wrong_str, correction = fix_extract_correction(exception)
          return false if correction.nil?
          !fix_apply_correction(code, wrong_str, correction).nil?
        end

        private

        def fix_correctable?(exception)
          exception.respond_to?(:corrections) && exception.is_a?(Exception)
        end

        def fix_extract_correction(exception)
          corrections = exception.corrections
          return [nil, nil] if corrections.nil? || corrections.empty?

          wrong_str = fix_wrong_string_from(exception)
          return [nil, nil] if wrong_str.nil? || wrong_str.to_s.empty?

          filtered = if defined?(DidYouMean::Levenshtein)
            corrections.select do |c|
              c_str = c.is_a?(Array) ? c.first.to_s : c.to_s
              DidYouMean::Levenshtein.distance(fix_normalize(wrong_str), fix_normalize(c_str)) <= MAX_EDIT_DISTANCE
            end
          else
            corrections
          end

          return [nil, nil] unless filtered.size == 1

          correction = filtered.first
          correction_str = correction.is_a?(Array) ? correction.first : correction
          [wrong_str.to_s, correction_str]
        end

        def fix_wrong_string_from(exception)
          case exception
          when NoMethodError then exception.name.to_s
          when NameError then exception.name.to_s
          when KeyError then exception.key.to_s
          when LoadError then exception.message[/cannot load such file -- (.+)/, 1]
          else
            if defined?(NoMatchingPatternKeyError) && exception.is_a?(NoMatchingPatternKeyError)
              exception.key.to_s
            end
          end
        end

        def fix_normalize(str)
          str.to_s.downcase
        end

        # Replaces wrong_str with correction in code. Uses gsub to fix all occurrences
        # (e.g. "foo.zeor? && bar.zeor?" both get corrected).
        def fix_apply_correction(code, wrong_str, correction_str)
          correction_display = correction_str.to_s
          patterns = [
            [wrong_str, correction_display],
            [":#{wrong_str}", ":#{correction_display}"],
            ["\"#{wrong_str}\"", "\"#{correction_display}\""],
            ["'#{wrong_str}'", "'#{correction_display}'"],
          ]
          patterns.each do |wrong_pattern, correct_pattern|
            escaped = Regexp.escape(wrong_pattern)
            new_code = code.gsub(/#{escaped}/, correct_pattern)
            return new_code if new_code != code
          end
          nil
        end
      end

      private

      def correctable?(exception)
        self.class.send(:fix_correctable?, exception)
      end

      def extract_correction(exception)
        self.class.send(:fix_extract_correction, exception)
      end

      def apply_correction(code, wrong_str, correction_str)
        self.class.send(:fix_apply_correction, code, wrong_str, correction_str)
      end
    end

    # Stores the last failed code and exception for the fix command.
    # Not thread-safe; intended for single-threaded IRB sessions.
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
