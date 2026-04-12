# frozen_string_literal: true

require "tempfile"
require "fileutils"

require_relative "helper"

module TestIRB
  class ReloadableRequireIntegrationTest < IntegrationTestCase
    def setup
      super

      omit "ReloadableRequire requires Ruby::Box" if !defined?(Ruby::Box) || !Ruby::Box.enabled?

      @envs["RUBY_BOX"] = "1"

      setup_lib_files

      write_rc <<~RUBY
        IRB.conf[:RELOADABLE_REQUIRE] = true
        $LOAD_PATH.unshift('#{@lib_dir}')
      RUBY
    end

    def teardown
      super
      FileUtils.rm_rf(@lib_dir) if @lib_dir
      @pwd_files&.each { |f| File.delete(f) if File.exist?(f) }
    end

    def test_require_enables_reload
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "require 'nested_a'"
        type "NESTED_A_VALUE"
        type "NESTED_B_VALUE"
        type "box_reload"
        type "exit!"
      end

      assert_include output, "=> \"from_a\""
      assert_include output, "=> \"from_b\""
      assert_include output, "Reloaded: #{@nested_a_path}"
      assert_include output, "Reloaded: #{@nested_b_path}"
    end

    def test_require_relative_from_irb_prompt_enables_reload
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "require_relative 'require_relative_lib'"
        type "REQUIRE_RELATIVE_LIB_VALUE"
        type "REQUIRE_RELATIVE_DEP"
        type "box_reload"
        type "exit!"
      end

      assert_include output, "=> 42"
      assert_include output, "=> \"dep\""
      assert_include output, "Reloaded: #{@require_relative_lib_path}"
      assert_include output, "Reloaded: #{@require_relative_dep_path}"
    end

    def test_require_with_nested_require_relative_enables_reload
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "require '#{@relative_nested_a_path}'"
        type "RELATIVE_NESTED_A"
        type "RELATIVE_NESTED_B"
        type "box_reload"
        type "exit!"
      end

      assert_include output, "=> \"from_a\""
      assert_include output, "=> \"from_b\""
      assert_include output, "Reloaded: #{@relative_nested_a_path}"
      assert_include output, "Reloaded: #{@relative_nested_b_path}"
    end

    def test_autoload_enables_reload
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "autoload :AutoloadMain, 'autoload_main'"
        type "AutoloadMain::VALUE"
        type "AUTOLOAD_DEP_VALUE"
        type "box_reload"
        type "exit!"
      end

      assert_include output, "=> \"main\""
      assert_include output, "=> \"dependency\""
      assert_include output, "Reloaded: #{@autoload_main_path}"
      assert_include output, "Reloaded: #{@autoload_dep_path}"
    end

    def test_reload_without_any_loaded_files
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "box_reload"
        type "exit!"
      end

      assert_include output, "No files to reload"
    end

    def test_reload_reflects_file_changes
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "require '#{@changeable_lib_path}'"
        type "CHANGEABLE_VALUE"
        type "File.write('#{@changeable_lib_path}', \"CHANGEABLE_VALUE = 'modified'\\n\")"
        type "box_reload"
        type "CHANGEABLE_VALUE"
        type "exit!"
      end

      assert_include output, "=> \"original\""
      assert_include output, "Reloaded: #{@changeable_lib_path}"
      assert_include output, "=> \"modified\""
    end

    def test_reload_command_without_reloadable_require_enabled
      write_rc <<~'RUBY'
        IRB.conf[:RELOADABLE_REQUIRE] = false
      RUBY

      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "box_reload"
        type "exit!"
      end

      assert_include output, "requires IRB.conf[:RELOADABLE_REQUIRE] = true"
    end

    def test_require_updates_loaded_features
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "require 'nested_a'"
        type "$LOADED_FEATURES.include?('#{@nested_a_path}')"
        type "$LOADED_FEATURES.include?('#{@nested_b_path}')"
        type "exit!"
      end

      # Both files should be in $LOADED_FEATURES
      assert_equal 2, output.scan("=> true").count
    end

    def test_autoload_updates_loaded_features
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "autoload :AutoloadMain, 'autoload_main'"
        type "AutoloadMain"
        type "$LOADED_FEATURES.include?('#{@autoload_main_path}')"
        type "$LOADED_FEATURES.include?('#{@autoload_dep_path}')"
        type "exit!"
      end

      # Both files should be in $LOADED_FEATURES
      assert_equal 2, output.scan("=> true").count
    end

    def test_reload_preserves_loaded_features
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "require 'nested_a'"
        type "$LOADED_FEATURES.include?('#{@nested_a_path}')"
        type "box_reload"
        type "$LOADED_FEATURES.include?('#{@nested_a_path}')"
        type "exit!"
      end

      # Both checks should return true (before and after reload)
      assert_equal 2, output.scan("=> true").count
    end

    def test_require_does_not_modify_load_path
      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "load_path_before = $LOAD_PATH.dup"
        type "require 'nested_a'"
        type "$LOAD_PATH == load_path_before"
        type "exit!"
      end

      assert_include output, "=> true"
    end

    private

    def setup_lib_files
      @lib_dir = Dir.mktmpdir
      @pwd_files = []

      # Nested require files (primary test files)
      @nested_b_path = create_lib_file("nested_b.rb", "NESTED_B_VALUE = 'from_b'\n")
      @nested_a_path = create_lib_file("nested_a.rb", "require 'nested_b'\nNESTED_A_VALUE = 'from_a'\n")

      # Nested require_relative files (for testing require that internally uses require_relative)
      @relative_nested_b_path = create_lib_file("relative_nested_b.rb", "RELATIVE_NESTED_B = 'from_b'\n")
      @relative_nested_a_path = create_lib_file(
        "relative_nested_a.rb",
        "require_relative 'relative_nested_b'\nRELATIVE_NESTED_A = 'from_a'\n"
      )

      # Files in Dir.pwd for require_relative from IRB prompt (with nested dependency)
      @require_relative_dep_path = create_pwd_file("require_relative_dep.rb", "REQUIRE_RELATIVE_DEP = 'dep'\n")
      @require_relative_lib_path = create_pwd_file(
        "require_relative_lib.rb",
        "require_relative 'require_relative_dep'\nREQUIRE_RELATIVE_LIB_VALUE = 42\n"
      )

      # Autoload files with nested require
      @autoload_dep_path = create_lib_file("autoload_dep.rb", "AUTOLOAD_DEP_VALUE = 'dependency'\n")
      @autoload_main_path = create_lib_file(
        "autoload_main.rb",
        "require 'autoload_dep'\nmodule AutoloadMain; VALUE = 'main'; end\n"
      )

      # Changeable file (for testing reload reflects changes)
      @changeable_lib_path = create_lib_file("changeable.rb", "CHANGEABLE_VALUE = 'original'\n")
    end

    def create_lib_file(name, content)
      path = File.join(@lib_dir, name)
      File.write(path, content)
      File.realpath(path)
    end

    def create_pwd_file(name, content)
      path = File.join(Dir.pwd, name)
      File.write(path, content)
      @pwd_files << path
      File.realpath(path)
    end
  end

  class ReloadCommandTest < TestCase
    def setup
      super
      @tmpdir = Dir.mktmpdir
      @valid_file = File.join(@tmpdir, "valid.rb")
      File.write(@valid_file, "VALID = true\n")
      @valid_file = File.realpath(@valid_file)

      require "irb"
      require "irb/command/reload"
      IRB.setup(__FILE__, argv: [])
      @original_reloadable = IRB.conf[:RELOADABLE_REQUIRE]
      @original_files = IRB.conf[:__RELOADABLE_FILES__]
      IRB.conf[:RELOADABLE_REQUIRE] = true
      IRB.conf[:__RELOADABLE_FILES__] = Set.new
    end

    def teardown
      super
      FileUtils.rm_rf(@tmpdir)
      IRB.conf[:RELOADABLE_REQUIRE] = @original_reloadable
      IRB.conf[:__RELOADABLE_FILES__] = @original_files
    end

    def test_reload_file_preserves_loaded_features_on_syntax_error
      $LOADED_FEATURES << @valid_file

      File.write(@valid_file, "def broken(")

      cmd = IRB::Command::Reload.new(nil)
      IRB.conf[:__RELOADABLE_FILES__] << @valid_file
      cmd.execute(nil)

      assert_equal true, $LOADED_FEATURES.include?(@valid_file)
    ensure
      $LOADED_FEATURES.delete(@valid_file)
    end

    def test_reload_file_preserves_loaded_features_on_load_error
      missing_file = File.join(@tmpdir, "missing.rb")
      $LOADED_FEATURES << missing_file

      cmd = IRB::Command::Reload.new(nil)
      IRB.conf[:__RELOADABLE_FILES__] << missing_file
      cmd.execute(nil)

      assert_equal true, $LOADED_FEATURES.include?(missing_file)
    ensure
      $LOADED_FEATURES.delete(missing_file)
    end
  end

  class ReloadableRequireMonkeyPatchTest < TestCase
    def setup
      super
      omit "ReloadableRequire requires Ruby::Box" if !defined?(Ruby::Box) || !Ruby::Box.enabled?
      require "irb/reloadable_require"
      @saved_original_require = Ruby::Box.instance_method(:__irb_original_require__)
    end

    def teardown
      super
      saved = @saved_original_require
      if saved
        Ruby::Box.define_method(:__irb_original_require__, saved)
      end
    end

    def test_original_require_alias_preserved_on_double_load
      IRB::ReloadableRequire.apply_autoload_hook

      # Double-loading the file should not overwrite __irb_original_require__
      # with the already-patched require method.
      load File.expand_path("../../lib/irb/reloadable_require.rb", __dir__)

      assert_equal @saved_original_require, Ruby::Box.instance_method(:__irb_original_require__)
    end
  end

  class ReloadableRequireDisabledTest < IntegrationTestCase
    def setup
      super

      omit "This test is for Ruby::Box disabled environment" if defined?(Ruby::Box) && Ruby::Box.enabled?
    end

    def test_reload_command_shows_error_without_ruby_box
      write_rc <<~'RUBY'
        IRB.conf[:RELOADABLE_REQUIRE] = true
      RUBY

      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "box_reload"
        type "exit!"
      end

      assert_include output, "requires IRB.conf[:RELOADABLE_REQUIRE] = true and Ruby::Box"
    end
  end
end
