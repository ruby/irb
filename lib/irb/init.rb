# frozen_string_literal: false
#
#   irb/init.rb - irb initialize module
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

module IRB # :nodoc:
  @CONF = {}
  @INITIALIZED = false
  # Displays current configuration.
  #
  # Modifying the configuration is achieved by sending a message to IRB.conf.
  #
  # See IRB@Configuration for more information.
  def IRB.conf
    @CONF
  end

  def @CONF.inspect
    array = []
    for k, v in sort{|a1, a2| a1[0].id2name <=> a2[0].id2name}
      case k
      when :MAIN_CONTEXT, :__TMP__EHV__
        array.push format("CONF[:%s]=...myself...", k.id2name)
      when :PROMPT
        s = v.collect{
          |kk, vv|
          ss = vv.collect{|kkk, vvv| ":#{kkk.id2name}=>#{vvv.inspect}"}
          format(":%s=>{%s}", kk.id2name, ss.join(", "))
        }
        array.push format("CONF[:%s]={%s}", k.id2name, s.join(", "))
      else
        array.push format("CONF[:%s]=%s", k.id2name, v.inspect)
      end
    end
    array.join("\n")
  end

  # Returns the current version of IRB, including release version and last
  # updated date.
  def IRB.version
    format("irb %s (%s)", @RELEASE_VERSION, @LAST_UPDATE_DATE)
  end

  def IRB.initialized?
    !!@INITIALIZED
  end

  # initialize config
  def IRB.setup(ap_path, argv: ::ARGV)
    IRB.init_config(ap_path)
    IRB.init_error
    IRB.parse_opts_with_option_parser(argv: argv)
    IRB.run_config
    IRB.load_modules

    unless @CONF[:PROMPT][@CONF[:PROMPT_MODE]]
      fail UndefinedPromptMode, @CONF[:PROMPT_MODE]
    end
    @INITIALIZED = true
  end

  # @CONF default setting
  def IRB.init_config(ap_path)
    # class instance variables
    @TRACER_INITIALIZED = false

    # default configurations
    unless ap_path and @CONF[:AP_NAME]
      ap_path = File.join(File.dirname(File.dirname(__FILE__)), "irb.rb")
    end
    @CONF[:VERSION] = version
    @CONF[:AP_NAME] = File::basename(ap_path, ".rb")

    @CONF[:IRB_NAME] = "irb"
    @CONF[:IRB_LIB_PATH] = File.dirname(__FILE__)

    @CONF[:RC] = true
    @CONF[:LOAD_MODULES] = []
    @CONF[:IRB_RC] = nil

    @CONF[:USE_SINGLELINE] = false unless defined?(ReadlineInputMethod)
    @CONF[:USE_COLORIZE] = (nc = ENV['NO_COLOR']).nil? || nc.empty?
    @CONF[:USE_AUTOCOMPLETE] = ENV.fetch("IRB_USE_AUTOCOMPLETE", "true") != "false"
    @CONF[:COMPLETOR] = ENV.fetch("IRB_COMPLETOR", "regexp").to_sym
    @CONF[:INSPECT_MODE] = true
    @CONF[:USE_TRACER] = false
    @CONF[:USE_LOADER] = false
    @CONF[:IGNORE_SIGINT] = true
    @CONF[:IGNORE_EOF] = false
    @CONF[:USE_PAGER] = true
    @CONF[:EXTRA_DOC_DIRS] = []
    @CONF[:ECHO] = nil
    @CONF[:ECHO_ON_ASSIGNMENT] = nil
    @CONF[:VERBOSE] = nil

    @CONF[:EVAL_HISTORY] = nil
    @CONF[:SAVE_HISTORY] = 1000

    @CONF[:BACK_TRACE_LIMIT] = 16

    @CONF[:PROMPT] = {
      :NULL => {
        :PROMPT_I => nil,
        :PROMPT_S => nil,
        :PROMPT_C => nil,
        :RETURN => "%s\n"
      },
      :DEFAULT => {
        :PROMPT_I => "%N(%m):%03n> ",
        :PROMPT_S => "%N(%m):%03n%l ",
        :PROMPT_C => "%N(%m):%03n* ",
        :RETURN => "=> %s\n"
      },
      :CLASSIC => {
        :PROMPT_I => "%N(%m):%03n:%i> ",
        :PROMPT_S => "%N(%m):%03n:%i%l ",
        :PROMPT_C => "%N(%m):%03n:%i* ",
        :RETURN => "%s\n"
      },
      :SIMPLE => {
        :PROMPT_I => ">> ",
        :PROMPT_S => "%l> ",
        :PROMPT_C => "?> ",
        :RETURN => "=> %s\n"
      },
      :INF_RUBY => {
        :PROMPT_I => "%N(%m):%03n> ",
        :PROMPT_S => nil,
        :PROMPT_C => nil,
        :RETURN => "%s\n",
        :AUTO_INDENT => true
      },
      :XMP => {
        :PROMPT_I => nil,
        :PROMPT_S => nil,
        :PROMPT_C => nil,
        :RETURN => "    ==>%s\n"
      }
    }

    @CONF[:PROMPT_MODE] = (STDIN.tty? ? :DEFAULT : :NULL)
    @CONF[:AUTO_INDENT] = true

    @CONF[:CONTEXT_MODE] = 4 # use a copy of TOPLEVEL_BINDING
    @CONF[:SINGLE_IRB] = false

    @CONF[:MEASURE] = false
    @CONF[:MEASURE_PROC] = {}
    @CONF[:MEASURE_PROC][:TIME] = proc { |context, code, line_no, &block|
      time = Time.now
      result = block.()
      now = Time.now
      puts 'processing time: %fs' % (now - time) if IRB.conf[:MEASURE]
      result
    }
    # arg can be either a symbol for the mode (:cpu, :wall, ..) or a hash for
    # a more complete configuration.
    # See https://github.com/tmm1/stackprof#all-options.
    @CONF[:MEASURE_PROC][:STACKPROF] = proc { |context, code, line_no, arg, &block|
      return block.() unless IRB.conf[:MEASURE]
      success = false
      begin
        require 'stackprof'
        success = true
      rescue LoadError
        puts 'Please run "gem install stackprof" before measuring by StackProf.'
      end
      if success
        result = nil
        arg = { mode: arg || :cpu } unless arg.is_a?(Hash)
        stackprof_result = StackProf.run(**arg) do
          result = block.()
        end
        case stackprof_result
        when File
          puts "StackProf report saved to #{stackprof_result.path}"
        when Hash
          StackProf::Report.new(stackprof_result).print_text
        else
          puts "Stackprof ran with #{arg.inspect}"
        end
        result
      else
        block.()
      end
    }
    @CONF[:MEASURE_CALLBACKS] = []

    @CONF[:LC_MESSAGES] = Locale.new

    @CONF[:AT_EXIT] = []

    @CONF[:COMMAND_ALIASES] = {
      # Symbol aliases
      :'$' => :show_source,
      :'@' => :whereami,
    }
  end

  def IRB.set_measure_callback(type = nil, arg = nil, &block)
    added = nil
    if type
      type_sym = type.upcase.to_sym
      if IRB.conf[:MEASURE_PROC][type_sym]
        added = [type_sym, IRB.conf[:MEASURE_PROC][type_sym], arg]
      end
    elsif IRB.conf[:MEASURE_PROC][:CUSTOM]
      added = [:CUSTOM, IRB.conf[:MEASURE_PROC][:CUSTOM], arg]
    elsif block_given?
      added = [:BLOCK, block, arg]
      found = IRB.conf[:MEASURE_CALLBACKS].find{ |m| m[0] == added[0] && m[2] == added[2] }
      if found
        found[1] = block
        return added
      else
        IRB.conf[:MEASURE_CALLBACKS] << added
        return added
      end
    else
      added = [:TIME, IRB.conf[:MEASURE_PROC][:TIME], arg]
    end
    if added
      IRB.conf[:MEASURE] = true
      found = IRB.conf[:MEASURE_CALLBACKS].find{ |m| m[0] == added[0] && m[2] == added[2] }
      if found
        # already added
        nil
      else
        IRB.conf[:MEASURE_CALLBACKS] << added if added
        added
      end
    else
      nil
    end
  end

  def IRB.unset_measure_callback(type = nil)
    if type.nil?
      IRB.conf[:MEASURE_CALLBACKS].clear
    else
      type_sym = type.upcase.to_sym
      IRB.conf[:MEASURE_CALLBACKS].reject!{ |t, | t == type_sym }
    end
    IRB.conf[:MEASURE] = nil if IRB.conf[:MEASURE_CALLBACKS].empty?
  end

  def IRB.init_error
    @CONF[:LC_MESSAGES].load("irb/error.rb")
  end

  require 'optparse'
  # option analyzing
  def IRB.parse_opts_with_option_parser(argv: ::ARGV)
    load_path = []

    parser = OptionParser.new(
      "Usage:  irb.rb [options] [programfile] [arguments]", # Banner
    )

    parser.on("-f", "Don't initialize from configuration file.") do
      @CONF[:RC] = false
    end
    parser.on("-d", "Set $DEBUG and $VERBOSE to true (same as `ruby -d`).") do
      $DEBUG = true
      $VERBOSE = true
    end
    parser.on("-w", "Suppress warnings (same as `ruby -w`).") do
      Warning[:deprecated] = $VERBOSE = true
    end
    parser.on("-W[level=2]", "Set warning level; 0=silence, 1=normal, 2=verbose", "(same as 'ruby -W').") do |value|
      case value
      when "0"
        $VERBOSE = nil
      when "1"
        $VERBOSE = false
      else
        Warning[:deprecated] = $VERBOSE = true
      end
    end
    parser.on("-r load-module", "Require load-module (same as 'ruby -r').") do |value|
      @CONF[:LOAD_MODULES].push value
    end
    parser.on("-I path", "Specify $LOAD_PATH directory (same as 'ruby -I').") do |value|
      load_path.concat(value.split(File::PATH_SEPARATOR))
    end
    parser.on("-U", "Set external and internal encoding to UTF-8.") do
      set_encoding("UTF-8", "UTF-8")
    end
    parser.on("-E ex[:in]", "--encoding=ex[:in]", "Specify the default external (ex) and internal (in) encodings", "(same as 'ruby -E').") do |value|
      set_encoding(*value.split(':', 2))
    end
    parser.on("--inspect", "Use 'inspect' for output.") do
      @CONF[:INSPECT_MODE] = true
    end
    parser.on("--noinspect", "Don't use 'inspect' for output.") do
      @CONF[:INSPECT_MODE] = false
    end
    parser.on("--no-pager", "Don't use pager.") do
      @CONF[:USE_PAGER] = false
    end
    parser.on("--singleline', '--readline', '--legacy", "Use single line editor module.") do
      @CONF[:USE_SINGLELINE] = true
    end
    parser.on("--nosingleline', '--noreadline", "Don't use single line editor module (default).") do
      @CONF[:USE_SINGLELINE] = false
    end
    parser.on("--multiline", "Use multiline editor module (default).") do
      @CONF[:USE_MULTILINE] = true
    end
    parser.on("--reidline", "Use multiline editor module (default).") do
      warn <<~MSG.strip
        --reidline is deprecated, please use --multiline instead.
      MSG
      @CONF[:USE_MULTILINE] = true
    end
    parser.on("--extra-doc-dir[=DIR]", "Add an extra doc dir for the doc dialog.") do |value|
      @CONF[:EXTRA_DOC_DIRS] << value
    end
    parser.on("--echo", "Show result (default).") do
      @CONF[:ECHO] = true
    end
    parser.on("--noecho", "Don't show result.") do
      @CONF[:ECHO] = false
    end
    parser.on("--echo-on-assignment", "Show result on assignment.") do
      @CONF[:ECHO_ON_ASSIGNMENT] = true
    end
    parser.on("--noecho-on-assignment", "Don't show result on assignment.") do
      @CONF[:ECHO_ON_ASSIGNMENT] = false
    end
    parser.on("--truncate-echo-on-assignment", "Show truncated result on assignment (default).") do
      @CONF[:ECHO_ON_ASSIGNMENT] = :truncate
    end
    parser.on("--verbose", "Show details.") do
      @CONF[:VERBOSE] = true
    end
    parser.on("--noverbose", "Don't show details.") do
      @CONF[:VERBOSE] = false
    end
    parser.on("--colorize", "Use color-highlighting (default).") do
      @CONF[:USE_COLORIZE] = true
    end
    parser.on("--nocolorize", "Don't use color-highlighting.") do
      @CONF[:USE_COLORIZE] = false
    end
    parser.on("--autocomplete", "Use auto-completion (default).") do
      @CONF[:USE_AUTOCOMPLETE] = true
    end
    parser.on("--noautocomplete", "Don't use auto-completion.") do
      @CONF[:USE_AUTOCOMPLETE] = false
    end
    parser.on("--regexp-completor", "Use Regexp based completion (default).") do
      @CONF[:COMPLETOR] = :regexp
    end
    parser.on("--type-completor", "Use type based completion.") do
      @CONF[:COMPLETOR] = :type
    end
    parser.on("--prompt-mode MODE', '--prompt MODE", "Set prompt mode. Pre-defined prompt modes are:", "'default', 'classic', 'simple', 'inf-ruby', 'xmp', 'null'.") do |value|
      prompt_mode = value.upcase.tr("-", "_").intern
      @CONF[:PROMPT_MODE] = prompt_mode
    end
    parser.on("--noprompt", "Don't output prompt.") do
      @CONF[:PROMPT_MODE] = :NULL
    end
    parser.on("--script", "Script mode (default, treat first argument as script).") do
      noscript = false
    end
    parser.on("--noscript", "No script mode (leave arguments in argv).") do
      noscript = true
    end
    parser.on("--inf-ruby-mode", "Use prompt appropriate for inf-ruby-mode on emacs.", "Suppresses --multiline and --singleline.") do
      @CONF[:PROMPT_MODE] = :INF_RUBY
    end
    parser.on("--sample-book-mode', '--simple-prompt", "Set prompt mode to 'simple'.") do
      @CONF[:PROMPT_MODE] = :SIMPLE
    end
    parser.on("--tracer", "Show stack trace for each command.") do
      @CONF[:USE_TRACER] = true
    end
    parser.on("--back-trace-limit[=N]", "Display backtrace top n and bottom n.") do |value|
      @CONF[:BACK_TRACE_LIMIT] = value.to_i
    end
    parser.on("--context-mode[=N]", "Set n[0-4] to method to create Binding Object,", "when new workspace was created.") do |value|
      @CONF[:CONTEXT_MODE] = value.to_i
    end
    parser.on("--single-irb", "Share self with sub-irb.") do
      @CONF[:SINGLE_IRB] = true
    end
    parser.on("-v', '--version", "Print the version of irb.") do
      print IRB.version, "\n"
      exit 0
    end

    options = { "back-trace-limit": 16 }
    parser.parse!(argv, into: options)

    while opt = argv.shift
      case opt
      when "--"
        if !noscript && (opt = argv.shift)
          @CONF[:SCRIPT] = opt
          $0 = opt
        end
        break
      when /^-./
        fail UnrecognizedSwitch, opt
      else
        if noscript
          argv.unshift(opt)
        else
          @CONF[:SCRIPT] = opt
          $0 = opt
        end
        break
      end
    end

    load_path.collect! do |path|
      /\A\.\// =~ path ? path : File.expand_path(path)
    end
    $LOAD_PATH.unshift(*load_path)
  end


  # Run the config file
  def IRB.run_config
    if @CONF[:RC]
      begin
        file = rc_file
        # Because rc_file always returns `HOME/.irbrc` even if no rc file is present, we can't warn users about missing rc files.
        # Otherwise, it'd be very noisy.
        load file if File.exist?(file)
      rescue StandardError, ScriptError => e
        warn "Error loading RC file '#{file}':\n#{e.full_message(highlight: false)}"
      end
    end
  end

  IRBRC_EXT = "rc"
  def IRB.rc_file(ext = IRBRC_EXT)
    if !@CONF[:RC_NAME_GENERATOR]
      rc_file_generators do |rcgen|
        @CONF[:RC_NAME_GENERATOR] ||= rcgen
        if File.exist?(rcgen.call(IRBRC_EXT))
          @CONF[:RC_NAME_GENERATOR] = rcgen
          break
        end
      end
    end
    case rc_file = @CONF[:RC_NAME_GENERATOR].call(ext)
    when String
      rc_file
    else
      fail IllegalRCNameGenerator
    end
  end

  # enumerate possible rc-file base name generators
  def IRB.rc_file_generators
    if irbrc = ENV["IRBRC"]
      yield proc{|rc| rc == "rc" ? irbrc : irbrc+rc}
    end
    if xdg_config_home = ENV["XDG_CONFIG_HOME"]
      irb_home = File.join(xdg_config_home, "irb")
      if File.directory?(irb_home)
        yield proc{|rc| irb_home + "/irb#{rc}"}
      end
    end
    if home = ENV["HOME"]
      yield proc{|rc| home+"/.irb#{rc}"}
      yield proc{|rc| home+"/.config/irb/irb#{rc}"}
    end
    current_dir = Dir.pwd
    yield proc{|rc| current_dir+"/.irb#{rc}"}
    yield proc{|rc| current_dir+"/irb#{rc.sub(/\A_?/, '.')}"}
    yield proc{|rc| current_dir+"/_irb#{rc}"}
    yield proc{|rc| current_dir+"/$irb#{rc}"}
  end

  # loading modules
  def IRB.load_modules
    for m in @CONF[:LOAD_MODULES]
      begin
        require m
      rescue LoadError => err
        warn "#{err.class}: #{err}", uplevel: 0
      end
    end
  end

  class << IRB
    private
    def set_encoding(extern, intern = nil, override: true)
      verbose, $VERBOSE = $VERBOSE, nil
      Encoding.default_external = extern unless extern.nil? || extern.empty?
      Encoding.default_internal = intern unless intern.nil? || intern.empty?
      [$stdin, $stdout, $stderr].each do |io|
        io.set_encoding(extern, intern)
      end
      if override
        @CONF[:LC_MESSAGES].instance_variable_set(:@override_encoding, extern)
      else
        @CONF[:LC_MESSAGES].instance_variable_set(:@encoding, extern)
      end
    ensure
      $VERBOSE = verbose
    end
  end
end
