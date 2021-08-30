require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "test/lib"
  t.libs << "lib"
  t.ruby_opts << "-rhelper"
  t.test_files = FileList["test/irb/test_*.rb"]
end

Rake::TestTask.new(:test_yamatanooroti) do |t|
  t.libs << 'test' << "test/lib"
  t.libs << 'lib'
  #t.loader = :direct
  t.ruby_opts << "-rhelper"
  t.pattern = 'test/irb/yamatanooroti/test_*.rb'
end

task :sync_tool do
  require 'fileutils'
  FileUtils.cp "../ruby/tool/lib/core_assertions.rb", "./test/lib"
  FileUtils.cp "../ruby/tool/lib/envutil.rb", "./test/lib"
  FileUtils.cp "../ruby/tool/lib/find_executable.rb", "./test/lib"
end

task :default => :test
