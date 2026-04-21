# frozen_string_literal: true

require_relative "color"
require_relative "version"

module IRB
  module StartupMessage
    TIPS = [
      'Type "help" for commands, "help <cmd>" for details',
      '"show_doc method" to view documentation',
      '"ls [object]" to see methods and properties',
      '"ls [object] -g pattern" to filter methods and properties',
      '"edit method" to open the method\'s source in editor',
      '"cd object" to navigate into an object',
      '"show_source method" to view source code',
      '"copy expr" to copy the output to clipboard',
      '"debug" to start integration with the "debug" gem',
      '"history -g pattern" to search history',
    ].freeze

    class << self
      def display
        logo_lines = load_logo
        info_lines = build_info_lines

        output = if logo_lines
          combine_logo_and_info(logo_lines, info_lines)
        else
          info_lines.join("\n")
        end

        # Add a blank line to not immediately touch warning messages
        puts
        puts output
        puts
      end

      private

      def load_logo
        encoding = STDOUT.external_encoding || Encoding.default_external
        return nil unless encoding == Encoding::UTF_8

        logo = IRB.send(:easter_egg_logo, :unicode_small)
        return nil unless logo

        logo.chomp.lines.map(&:chomp)
      end

      def build_info_lines
        version_line = "#{Color.colorize('IRB', [:BOLD])} v#{VERSION} - Ruby #{RUBY_VERSION}"
        tip_line = colorize_tip(TIPS.sample)
        dir_line = Color.colorize(short_pwd, [:CYAN])

        [version_line, tip_line, dir_line]
      end

      def colorize_tip(tip)
        tip.gsub(/"[^"]*"/) { |match| Color.colorize(match, [:YELLOW]) }
      end

      def combine_logo_and_info(logo_lines, info_lines)
        max_lines = [logo_lines.size, info_lines.size].max
        lines = max_lines.times.map do |i|
          logo_part = logo_lines[i] || ""
          info_part = info_lines[i] || ""
          colored_logo = Color.colorize(logo_part, [:RED, :BOLD])
          "#{colored_logo}  #{info_part}"
        end
        lines.join("\n")
      end

      def short_pwd
        dir = Dir.pwd
        home = ENV['HOME']
        if home && (dir == home || dir.start_with?("#{home}/"))
          dir = "~#{dir[home.size..]}"
        end
        dir
      end
    end
  end
end
