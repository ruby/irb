# frozen_string_literal: false
#
#   irb/completion.rb -
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#       From Original Idea of shugo@ruby-lang.org
#

require_relative 'ruby-lex'

module IRB
  module InputCompletor # :nodoc:
    using Module.new {
      refine ::Binding do
        def eval_methods
          ::Kernel.instance_method(:methods).bind(eval("self")).call
        end

        def eval_private_methods
          ::Kernel.instance_method(:private_methods).bind(eval("self")).call
        end

        def eval_instance_variables
          ::Kernel.instance_method(:instance_variables).bind(eval("self")).call
        end

        def eval_global_variables
          ::Kernel.global_variables
        end

        def eval_constants
          [Object, *eval('::Module.nesting')].flat_map(&:constants).uniq.sort rescue []
        end

        def eval_class_variables
          mod = eval('::Module.nesting').first
          mod&.class_variables || [] rescue []
        end

        def eval_instance_variable_get(name)
          ::Kernel.instance_method(:instance_variable_get).bind_call(eval('self'), name) rescue nil
        end

        def eval_class_variable_get(name)
          mod = eval('::Module.nesting').first
          mod&.class_variable_get(name) rescue nil
        end
      end
    }

    # Set of reserved words used by Ruby, you should not use these for
    # constants or variables
    ReservedWords = %w[
      __ENCODING__ __LINE__ __FILE__
      BEGIN END
      alias and
      begin break
      case class
      def defined? do
      else elsif end ensure
      false for
      if in
      module
      next nil not
      or
      redo rescue retry return
      self super
      then true
      undef unless until
      when while
      yield
    ]

    BASIC_WORD_BREAK_CHARACTERS = " \t\n`><=;|&{("

    GEM_PATHS =
      if defined?(Gem::Specification)
        Gem::Specification.latest_specs(true).map { |s|
          s.require_paths.map { |p|
            if File.absolute_path?(p)
              p
            else
              File.join(s.full_gem_path, p)
            end
          }
        }.flatten
      else
        []
      end.freeze

    def self.retrieve_gem_and_system_load_path
      candidates = (GEM_PATHS | $LOAD_PATH)
      candidates.map do |p|
        if p.respond_to?(:to_path)
          p.to_path
        else
          String(p) rescue nil
        end
      end.compact.sort
    end

    def self.retrieve_files_to_require_from_load_path
      @@files_from_load_path ||=
        (
          shortest = []
          rest = retrieve_gem_and_system_load_path.each_with_object([]) { |path, result|
            begin
              names = Dir.glob("**/*.{rb,#{RbConfig::CONFIG['DLEXT']}}", base: path)
            rescue Errno::ENOENT
              nil
            end
            next if names.empty?
            names.map! { |n| n.sub(/\.(rb|#{RbConfig::CONFIG['DLEXT']})\z/, '') }.sort!
            shortest << names.shift
            result.concat(names)
          }
          shortest.sort! | rest
        )
    end

    def self.retrieve_files_to_require_relative_from_current_dir
      @@files_from_current_dir ||= Dir.glob("**/*.{rb,#{RbConfig::CONFIG['DLEXT']}}", base: '.').map { |path|
        path.sub(/\.(rb|#{RbConfig::CONFIG['DLEXT']})\z/, '')
      }
    end

    def self.retrieve_completion_sexp_nodes(code)
      tokens = RubyLex.ripper_lex_without_warning(code)

      # remove error tokens
      tokens.pop while tokens&.last&.tok&.empty?

      event = tokens.last&.event
      tok = tokens.last&.tok

      if (event == :on_ignored_by_ripper || event == :on_op || event == :on_period) && (tok == '.' || tok == '::' || tok == '&.')
        suffix = tok == '::' ? 'Const' : 'method'
        tok = ''
      elsif event == :on_symbeg
        suffix = 'symbol'
        tok = ''
      elsif event == :on_ident || event == :on_kw
        suffix = 'method'
      elsif event == :on_const
        suffix = 'Const'
      elsif event == :on_tstring_content
        suffix = 'string'
      elsif event == :on_gvar
        suffix = '$gvar'
      elsif event == :on_ivar
        suffix = '@ivar'
      elsif event == :on_cvar
        suffix = '@@cvar'
      else
        return
      end

      code = code.delete_suffix(tok)
      last_opens = IRB::NestingParser.open_tokens(tokens)
      closing_code = IRB::NestingParser.closing_code(last_opens)
      sexp = Ripper.sexp("#{code}#{suffix}#{closing_code}")
      return unless sexp

      lines = code.split("\n", -1)
      row = lines.empty? ? 1 : lines.size
      col = lines.last&.bytesize || 0
      matched_nodes = find_target_from_sexp(sexp, row, col)
      [matched_nodes, tok] if matched_nodes
    end

    def self.find_target_from_sexp(sexp, row, col)
      return unless sexp.is_a? Array

      sexp.each do |child|
        event, tok, pos = child
        if event.is_a?(Symbol) && tok.is_a?(String) && pos == [row, col]
          return [child]
        else
          result = find_target_from_sexp(child, row, col)
          if result
            result.unshift child
            return result
          end
        end
      end
      nil
    end

    def self.evaluate_receiver_with_visibility(receiver_node, bind)
      event, *data = receiver_node
      case event
      when :var_ref
        if (value, visibility = evaluate_var_ref_with_visibility(data[0], bind))
          [value.nil? ? NilClass : nil, value, visibility]
        end
      when :const_path_ref
        _reciever_class, reciever, _visibility = evaluate_receiver_with_visibility(data[0], bind)
        if reciever
          [nil, reciever.const_get(data[1][1]), false] rescue nil
        end
      when :top_const_ref
        [nil, Object.const_get(data[0][1]), false] rescue nil
      when :array
        [Array, nil, false]
      when :hash
        [Hash, nil, false]
      when :lambda
        [Proc, nil, false]
      when :symbol_literal, :dyna_symbol, :def
        [Symbol, nil, false]
      when :string_literal, :xstring_literal
        [String, nil, false]
      when :@int
        [Integer, nil, false]
      when :@float
        [Float, nil, false]
      when :@rational
        [Rational, nil, false]
      when :@imaginary
        [Complex, nil, false]
      when :regexp_literal
        [Regexp, nil, false]
      end
    end

    def self.evaluate_var_ref_with_visibility(node, bind)
      type, value = node
      case type
      when :@kw
        case value
        when 'self'
          [bind.eval('self'), true]
        when 'true'
          [true, false]
        when 'false'
          [false, false]
        when 'nil'
          [nil, false]
        end
      when :@ident
        [bind.local_variable_get(value), false]
      when :@gvar
        [eval(value), false] if global_variables.include? value
      when :@ivar
        [bind.eval_instance_variable_get(value), false]
      when :@cvar
        [bind.class_variable_get(value), false]
      when :@const
        [bind.eval(value), false] rescue nil
      end
    end

    def self.retrieve_completion_target(code)
      matched_nodes, name = retrieve_completion_sexp_nodes(code)
      return unless matched_nodes

      *parents, expression, (target_event,) = matched_nodes

      case target_event
      when :@gvar
        return [:gvar, name]
      when :@ivar
        return [:ivar, name]
      when :@cvar
        return [:cvar, name]
      end
      return unless expression

      if target_event == :@tstring_content
        req_event, (ident_event, ident_name) = parents[-4]
        if req_event == :command && ident_event == :@ident && (ident_name == 'require' || ident_name == 'require_relative')
          return [ident_name.to_sym, name.rstrip]
        end
      end

      expression_event = expression[0]
      case expression_event
      when :symbol
        [:symbol, name]
      when :vcall
        [:lvar_or_method, name]
      when :var_ref
        if target_event == :@ident
          [:lvar_or_method, name]
        elsif target_event == :@const
          [:const_or_method, name]
        end
      when :const_ref
        [:const, name]
      when :const_path_ref
        [:const, name, expression[1]]
      when :top_const_ref
        [:top_const, name]
      when :def
        [:const_or_lvar_or_method, name]
      when :call, :defs
        [:call, name, expression[1]]
      end
    end

    def self.retrieve_completion_data(code, bind:)
      lvars_code = RubyLex.generate_local_variables_assign_code(bind.local_variables)
      type, name, receiver_node = retrieve_completion_target("#{lvars_code}\n#{code}")
      receiver_class, receiver_object, public_visibility = evaluate_receiver_with_visibility(receiver_node, bind) if receiver_node
      [type, name, receiver_class, receiver_object, public_visibility]
    end

    def self.completion_candidates(completion_data, bind:)
      type, name, receiver_class, receiver_object, public_visibility = completion_data
      return [] unless type

      case type
      when :require
        retrieve_files_to_require_from_load_path
      when :require_relative
        retrieve_files_to_require_relative_from_current_dir
      when :symbol
        if name.empty?
          []
        else
          Symbol.all_symbols.filter_map do |s|
            s.inspect[1..]
          rescue EncodingError
            # ignore for truffleruby
          end
        end
      when :gvar
        global_variables
      when :ivar
        bind.eval_instance_variables
      when :cvar
        bind.eval_class_variables
      when :call
        if receiver_class
          public_visibility ? receiver_class.public_instance_methods : receiver_class.instance_methods
        elsif receiver_object.nil?
          []
        else
          public_visibility ? receiver_object.public_methods | receiver_object.private_methods : receiver_object.public_methods
        end
      when :top_const
        Object.constants.sort
      when :const
        if receiver_object
          receiver_object.constants.sort
        else
          bind.eval_constants.sort
        end
      when :const_or_method
        (bind.eval_constants | bind.eval_methods | bind.eval_private_methods | ReservedWords).map(&:to_s).sort
      when :const_or_lvar_or_method
        (bind.eval_constants | bind.local_variables | bind.eval_methods | bind.eval_private_methods | ReservedWords).map(&:to_s).sort
      when :lvar_or_method
        (bind.local_variables | bind.eval_methods | bind.eval_private_methods | ReservedWords).map(&:to_s).sort
      else
        []
      end
    end

    @@previous_completion_data = nil

    def self.previous_completion_data
      @@previous_completion_data
    end

    CompletionProc = lambda { |target, preposing, postposing|
      context = IRB.conf[:MAIN_CONTEXT]
      bind = context.workspace.binding
      completion_data = retrieve_completion_data("#{preposing}#{target}", bind: bind)
      candidates = completion_candidates(completion_data, bind: bind)

      # Hack to use completion_data from SHOW_DOC_DIALOG and from PerfectMatchedProc
      @@previous_completion_data = completion_data

      type, name, = completion_data
      return [] unless type

      prefix = target.delete_suffix name
      candidates.map(&:to_s).select { |s| s.start_with? name }.map do |s|
        prefix + s
      end
    }

    def self.retrieve_doc_namespace(target, completion_data, bind:)
      name = target[/(\$|@|@@)?[a-zA-Z_0-9]+[?=!]?\z/]
      return unless name

      type, _name, receiver_class, receiver_object, _public_visibility = completion_data
      receiver_class ||= receiver_object.class
      case type
      when :call
        if receiver_object.is_a?(Module)
          "#{receiver_object}.#{name}"
        else
          "#{receiver_class}.#{name}"
        end
      when :top_const
        name
      when :const
        "#{receiver_object}::#{name}" if receiver_object.is_a?(Module)
      when :const_or_method
        name
      when :ivar
        bind.eval_instance_variable_get(name).class.to_s rescue nil
      when :lvar_or_method
        if bind.local_variables.include?(name.to_sym)
          bind.local_variable_get(name).class.to_s
        else
          "#{bind.eval('self').class}.#{name}"
        end
      end
    end

    PerfectMatchedProc = ->(matched, bind: IRB.conf[:MAIN_CONTEXT].workspace.binding) {
      begin
        require 'rdoc'
      rescue LoadError
        return
      end

      RDocRIDriver ||= RDoc::RI::Driver.new

      if matched =~ /\A(?:::)?RubyVM/ and not ENV['RUBY_YES_I_AM_NOT_A_NORMAL_USER']
        IRB.__send__(:easter_egg)
        return
      end

      namespace = retrieve_doc_namespace(matched, previous_completion_data, bind: bind)
      return unless namespace

      begin
        RDocRIDriver.display_names([namespace])
      rescue RDoc::RI::Driver::NotFoundError
      end
    }
  end
end
