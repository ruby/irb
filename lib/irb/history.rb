module IRB
  module HistorySavingAbility # :nodoc:
    def HistorySavingAbility.extended(obj)
      IRB.conf[:AT_EXIT].push proc{obj.save_history}
      obj.load_history
      obj
    end

    def load_history
      history = self.class::HISTORY
      @loaded_history_lines = 0

      if history_file = IRB.conf[:HISTORY_FILE]
        history_file = File.expand_path(history_file)
      end
      history_file = IRB.rc_file("_history") unless history_file
      if File.exist?(history_file)
        File.open(history_file, "r:#{IRB.conf[:LC_MESSAGES].encoding}") do |f|
          f.each { |l|
            l = l.chomp
            if self.class == RelineInputMethod and history.last&.end_with?("\\")
              history.last.delete_suffix!("\\")
              history.last << "\n" << l
            else
              history << l
            end
          }
        end
        @loaded_history_lines = history.size
        @loaded_history_mtime = File.mtime(history_file)
      end
    end

    def save_history
      if num = IRB.conf[:SAVE_HISTORY] and (num = num.to_i) != 0
        if history_file = IRB.conf[:HISTORY_FILE]
          history_file = File.expand_path(history_file)
        end
        history_file = IRB.rc_file("_history") unless history_file

        # Change the permission of a file that already exists[BUG #7694]
        begin
          if File.stat(history_file).mode & 066 != 0
            File.chmod(0600, history_file)
          end
        rescue Errno::ENOENT
        rescue Errno::EPERM
          return
        rescue
          raise
        end

        from = 0
        if File.exist?(history_file) &&
           File.mtime(history_file) != @loaded_history_mtime
          from = @loaded_history_lines
          append_history = true
        end

        hist = []
        from.upto(self.class::HISTORY.size - 1) do |index|
          hist << self.class::HISTORY[index].split("\n").join("\\\n")
        end

        File.open(history_file, (append_history ? 'a' : 'w'), 0o600, encoding: IRB.conf[:LC_MESSAGES]&.encoding) do |f|
          unless append_history
            begin
              hist = hist.last(num) if hist.size > num and num > 0
            rescue RangeError # bignum too big to convert into `long'
              # Do nothing because the bignum should be treated as inifinity
            end
          end
          f.puts(hist)
        end
      end
    end
  end
end
