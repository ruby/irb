require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "test/lib"
  t.libs << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
end

Rake::TestTask.new(:test_yamatanooroti) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  #t.loader = :direct
  t.pattern = 'test/irb/yamatanooroti/test_*.rb'
end

task :default => :test
