# frozen_string_literal: true
#
#   irb/input-method.rb - input methods used irb
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

require_relative 'completion'
require_relative "history"
require 'io/console'
require 'reline'

module IRB
  class InputMethod
    BASIC_WORD_BREAK_CHARACTERS = " \t\n`><=;|&{("

    # The irb prompt associated with this input method
    attr_accessor :prompt

    # Reads the next line from this input method.
    #
    # See IO#gets for more information.
    def gets
      fail NotImplementedError
    end
    public :gets

    def winsize
      if instance_variable_defined?(:@stdout) && @stdout.tty?
        winsize = @stdout.winsize
        # If width or height is 0, something is wrong.
        return winsize unless winsize.include? 0
      end
      [24, 80]
    end

    # Whether this input method is still readable when there is no more data to
    # read.
    #
    # See IO#eof for more information.
    def readable_after_eof?
      false
    end

    def support_history_saving?
      false
    end

    def prompting?
      false
    end

    # For debug message
    def inspect
      'Abstract InputMethod'
    end
  end

  class StdioInputMethod < InputMethod
    # Creates a new input method object
    def initialize
      @line_no = 0
      @line = []
      @stdin = IO.open(STDIN.to_i, :external_encoding => IRB.conf[:LC_MESSAGES].encoding, :internal_encoding => "-")
      @stdout = IO.open(STDOUT.to_i, 'w', :external_encoding => IRB.conf[:LC_MESSAGES].encoding, :internal_encoding => "-")
    end

    # Reads the next line from this input method.
    #
    # See IO#gets for more information.
    def gets
      # Workaround for debug compatibility test https://github.com/ruby/debug/pull/1100
      puts if ENV['RUBY_DEBUG_TEST_UI']

      print @prompt
      line = @stdin.gets
      @line[@line_no += 1] = line
    end

    # Whether the end of this input method has been reached, returns +true+ if
    # there is no more data to read.
    #
    # See IO#eof? for more information.
    def eof?
      if @stdin.wait_readable(0.00001)
        c = @stdin.getc
        result = c.nil? ? true : false
        @stdin.ungetc(c) unless c.nil?
        result
      else # buffer is empty
        false
      end
    end

    # Whether this input method is still readable when there is no more data to
    # read.
    #
    # See IO#eof for more information.
    def readable_after_eof?
      true
    end

    def prompting?
      STDIN.tty?
    end

    # Returns the current line number for #io.
    #
    # #line counts the number of times #gets is called.
    #
    # See IO#lineno for more information.
    def line(line_no)
      @line[line_no]
    end

    # The external encoding for standard input.
    def encoding
      @stdin.external_encoding
    end

    # For debug message
    def inspect
      'StdioInputMethod'
    end
  end

  # Use a File for IO with irb, see InputMethod
  class FileInputMethod < InputMethod
    class << self
      def open(file, &block)
        begin
          io = new(file)
          block.call(io)
        ensure
          io&.close
        end
      end
    end

    # Creates a new input method object
    def initialize(file)
      @io = file.is_a?(IO) ? file : File.open(file)
      @external_encoding = @io.external_encoding
    end

    # Whether the end of this input method has been reached, returns +true+ if
    # there is no more data to read.
    #
    # See IO#eof? for more information.
    def eof?
      @io.closed? || @io.eof?
    end

    # Reads the next line from this input method.
    #
    # See IO#gets for more information.
    def gets
      print @prompt
      @io.gets
    end

    # The external encoding for standard input.
    def encoding
      @external_encoding
    end

    # For debug message
    def inspect
      'FileInputMethod'
    end

    def close
      @io.close
    end
  end

  class ReadlineInputMethod < StdioInputMethod
    class << self
      def initialize_readline
        return if defined?(self::Readline)

        begin
          require 'readline'
          const_set(:Readline, ::Readline)
        rescue LoadError
          const_set(:Readline, ::Reline)
        end
        const_set(:HISTORY, self::Readline::HISTORY)
      end
    end

    include HistorySavingAbility

    # Creates a new input method object using Readline
    def initialize
      self.class.initialize_readline
      if Readline.respond_to?(:encoding_system_needs)
        IRB.__send__(:set_encoding, Readline.encoding_system_needs.name, override: false)
      end

      super

      @eof = false
      @completor = RegexpCompletor.new

      if Readline.respond_to?("basic_word_break_characters=")
        Readline.basic_word_break_characters = BASIC_WORD_BREAK_CHARACTERS
      end
      Readline.completion_append_character = nil
      Readline.completion_proc = ->(target) {
        bind = IRB.conf[:MAIN_CONTEXT].workspace.binding
        @completor.completion_candidates('', target, '', bind: bind)
      }
    end

    def completion_info
      'RegexpCompletor'
    end

    # Reads the next line from this input method.
    #
    # See IO#gets for more information.
    def gets
      Readline.input = @stdin
      Readline.output = @stdout
      if l = Readline.readline(@prompt, false)
        Readline::HISTORY.push(l) if !l.empty? && l != Readline::HISTORY.to_a.last
        @line[@line_no += 1] = l + "\n"
      else
        @eof = true
        l
      end
    end

    # Whether the end of this input method has been reached, returns +true+
    # if there is no more data to read.
    #
    # See IO#eof? for more information.
    def eof?
      @eof
    end

    def prompting?
      true
    end

    # For debug message
    def inspect
      readline_impl = Readline == ::Reline ? 'Reline' : 'ext/readline'
      str = "ReadlineInputMethod with #{readline_impl} #{Readline::VERSION}"
      inputrc_path = File.expand_path(ENV['INPUTRC'] || '~/.inputrc')
      str += " and #{inputrc_path}" if File.exist?(inputrc_path)
      str
    end
  end

  class RelineInputMethod < StdioInputMethod
    HISTORY = Reline::HISTORY
    ALT_KEY_NAME = RUBY_PLATFORM.match?(/darwin/) ? "Option" : "Alt"
    PRESS_ALT_D_TO_READ_FULL_DOC = "Press #{ALT_KEY_NAME}+d to read the full document".freeze
    PRESS_ALT_D_TO_SEE_MORE = "Press #{ALT_KEY_NAME}+d to see more".freeze
    ALT_D_SEQUENCES = [
      [27, 100], # Normal Alt+d when convert-meta isn't used.
      # When option/alt is not configured as a meta key in terminal emulator,
      # option/alt + d will send a unicode character depend on OS keyboard setting.
      [195, 164], # "ä" in somewhere (FIXME: environment information is unknown).
      [226, 136, 130] # "∂" Alt+d on Mac keyboard.
    ].freeze
    include HistorySavingAbility
    # Creates a new input method object using Reline
    def initialize(completor)
      IRB.__send__(:set_encoding, Reline.encoding_system_needs.name, override: false)

      super()

      @eof = false
      @completor = completor

      Reline.basic_word_break_characters = BASIC_WORD_BREAK_CHARACTERS
      Reline.completion_append_character = nil
      Reline.completer_quote_characters = ''
      Reline.completion_proc = ->(target, preposing, postposing) {
        bind = IRB.conf[:MAIN_CONTEXT].workspace.binding
        @completion_params = [preposing, target, postposing, bind]
        @completor.completion_candidates(preposing, target, postposing, bind: bind)
      }
      Reline.output_modifier_proc = proc do |input, complete:|
        IRB.CurrentContext.colorize_input(input, complete: complete)
      end
      Reline.dig_perfect_match_proc = ->(matched) { display_document(matched) }
      Reline.autocompletion = IRB.conf[:USE_AUTOCOMPLETE]

      if IRB.conf[:USE_AUTOCOMPLETE]
        begin
          require 'rdoc'
          Reline.add_dialog_proc(:show_doc, show_doc_dialog_proc, Reline::DEFAULT_DIALOG_CONTEXT)
        rescue LoadError
        end
      end
    end

    def completion_info
      autocomplete_message = Reline.autocompletion ? 'Autocomplete' : 'Tab Complete'
      "#{autocomplete_message}, #{@completor.inspect}"
    end

    def check_termination(&block)
      @check_termination_proc = block
    end

    def dynamic_prompt(&block)
      @prompt_proc = block
    end

    def auto_indent(&block)
      @auto_indent_proc = block
    end

    def retrieve_document_target(matched)
      preposing, _target, postposing, bind = @completion_params
      result = @completor.doc_namespace(preposing, matched, postposing, bind: bind)
      case result
      when DocumentTarget, nil
        result
      when Array
        MethodDocument.new(*result)
      when String
        MethodDocument.new(result)
      end
    end

    def rdoc_ri_driver
      return @rdoc_ri_driver if defined?(@rdoc_ri_driver)

      begin
        require 'rdoc'
      rescue LoadError
        @rdoc_ri_driver = nil
      else
        options = {}
        options[:extra_doc_dirs] = IRB.conf[:EXTRA_DOC_DIRS] unless IRB.conf[:EXTRA_DOC_DIRS].empty?
        @rdoc_ri_driver = RDoc::RI::Driver.new(options)
      end
    end

    def show_doc_dialog_proc
      input_method = self # self is changed in the lambda below.
      ->() {
        dialog.trap_key = nil

        if just_cursor_moving && completion_journey_data.nil?
          return nil
        end
        cursor_pos_to_render, result, pointer, autocomplete_dialog = context.pop(4)
        return nil if result.nil? || pointer.nil? || pointer < 0

        matched_text = result[pointer]
        show_easter_egg = matched_text&.match?(/\ARubyVM/) && !ENV['RUBY_YES_I_AM_NOT_A_NORMAL_USER']
        target = show_easter_egg ? nil : input_method.retrieve_document_target(matched_text)

        x, width = input_method.dialog_doc_position(cursor_pos_to_render, autocomplete_dialog, screen_width)
        return nil unless x

        dialog.trap_key = ALT_D_SEQUENCES
        open_doc = key.match?(dialog.name)

        contents = case target
        when CommandDocument
          input_method.command_doc_dialog_contents(target.name, width, open_doc: open_doc)
        when MethodDocument
          input_method.rdoc_dialog_contents(target.name, width, open_doc: open_doc)
        else
          if show_easter_egg
            input_method.easter_egg_dialog_contents(open_doc: open_doc)
          end
        end
        return nil unless contents

        contents = contents.take(preferred_dialog_height)
        y = cursor_pos_to_render.y
        Reline::DialogRenderInfo.new(pos: Reline::CursorPos.new(x, y), contents: contents, width: width, bg_color: '49')
      }
    end

    def command_doc_dialog_contents(command_name, width, open_doc: false)
      command_class = IRB::Command.load_command(command_name)
      return unless command_class

      if open_doc
        content = command_class.help_message || command_class.description
        begin
          print "\e[?1049h"
          Pager.page_content(content)
        ensure
          print "\e[?1049l"
        end
      end

      [PRESS_ALT_D_TO_READ_FULL_DOC, ""] + command_class.doc_dialog_content(command_name, width)
    end

    def easter_egg_dialog_contents(open_doc: false)
      IRB.__send__(:easter_egg) if open_doc
      type = STDOUT.external_encoding == Encoding::UTF_8 ? :unicode : :ascii
      lines = IRB.send(:easter_egg_logo, type).split("\n")
      lines[0][0, PRESS_ALT_D_TO_SEE_MORE.size] = PRESS_ALT_D_TO_SEE_MORE
      lines
    end

    def rdoc_dialog_contents(name, width, open_doc: false)
      driver = rdoc_ri_driver
      return unless driver

      if open_doc
        begin
          print "\e[?1049h"
          driver.display_names([name])
        rescue RDoc::RI::Driver::NotFoundError
        ensure
          print "\e[?1049l"
        end
      end

      name = driver.expand_name(name)

      doc = if name =~ /#|\./
        d = RDoc::Markup::Document.new
        driver.add_method(d, name)
        d
      else
        found, klasses, includes, extends = driver.classes_and_includes_and_extends_for(name)
        if found.empty?
          d = RDoc::Markup::Document.new
          driver.add_method(d, name)
          d
        else
          driver.class_document(name, found, klasses, includes, extends)
        end
      end

      formatter = RDoc::Markup::ToAnsi.new
      formatter.width = width
      [PRESS_ALT_D_TO_READ_FULL_DOC] + doc.accept(formatter).split("\n")
    rescue RDoc::RI::Driver::NotFoundError
    end

    def dialog_doc_position(cursor_pos_to_render, autocomplete_dialog, screen_width)
      width = 40
      right_x = cursor_pos_to_render.x + autocomplete_dialog.width
      if right_x + width > screen_width
        right_width = screen_width - (right_x + 1)
        left_x = autocomplete_dialog.column - width
        left_x = 0 if left_x < 0
        left_width = width > autocomplete_dialog.column ? autocomplete_dialog.column : width
        if right_width.positive? && left_width.positive?
          if right_width >= left_width
            width = right_width
            x = right_x
          else
            width = left_width
            x = left_x
          end
        elsif right_width.positive? && left_width <= 0
          width = right_width
          x = right_x
        elsif right_width <= 0 && left_width.positive?
          width = left_width
          x = left_x
        else
          return nil
        end
      else
        x = right_x
      end
      [x, width]
    end

    def display_document(matched)
      target = retrieve_document_target(matched)
      return unless target

      case target
      when CommandDocument
        command_class = IRB::Command.load_command(target.name)
        if command_class
          content = command_class.help_message || command_class.description
          Pager.page_content(content)
        end
      when MethodDocument
        driver = rdoc_ri_driver
        return unless driver

        if matched =~ /\A(?:::)?RubyVM/ && !ENV['RUBY_YES_I_AM_NOT_A_NORMAL_USER']
          IRB.__send__(:easter_egg)
          return
        end

        if target.names.length > 1
          out = RDoc::Markup::Document.new
          target.names.each do |m|
            begin
              driver.add_method(out, m)
            rescue RDoc::RI::Driver::NotFoundError
            end
          end
          driver.display(out)
        else
          begin
            driver.display_names([target.name])
          rescue RDoc::RI::Driver::NotFoundError
          end
        end
      end
    end

    # Reads the next line from this input method.
    #
    # See IO#gets for more information.
    def gets
      Reline.input = @stdin
      Reline.output = @stdout
      Reline.prompt_proc = @prompt_proc
      Reline.auto_indent_proc = @auto_indent_proc if @auto_indent_proc
      if l = Reline.readmultiline(@prompt, false, &@check_termination_proc)
        Reline::HISTORY.push(l) if !l.empty? && l != Reline::HISTORY.to_a.last
        @line[@line_no += 1] = l + "\n"
      else
        @eof = true
        l
      end
    end

    # Whether the end of this input method has been reached, returns +true+
    # if there is no more data to read.
    #
    # See IO#eof? for more information.
    def eof?
      @eof
    end

    def prompting?
      true
    end

    # For debug message
    def inspect
      config = Reline::Config.new
      str = "RelineInputMethod with Reline #{Reline::VERSION}"
      inputrc_path = File.expand_path(config.inputrc_path)
      str += " and #{inputrc_path}" if File.exist?(inputrc_path)
      str
    end
  end

  class ReidlineInputMethod < RelineInputMethod
    def initialize
      warn <<~MSG.strip
        IRB::ReidlineInputMethod is deprecated, please use IRB::RelineInputMethod instead.
      MSG
      super
    end
  end
end
