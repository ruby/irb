source "https://rubygems.org"

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

gemspec

group :development do
  gem "bundler"
  is_unix = RUBY_PLATFORM =~ /(aix|darwin|linux|(net|free|open)bsd|cygwin|solaris|irix|hpux)/i
  is_truffleruby = RUBY_DESCRIPTION =~ /truffleruby/
  gem 'vterm', '>= 0.0.5' if is_unix && ENV['WITH_VTERM']
  gem 'yamatanooroti', '>= 0.0.6'
  gem "rake"
  gem "stackprof" if is_unix && !is_truffleruby
end
