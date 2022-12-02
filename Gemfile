source "https://rubygems.org"

gemspec

group :development do
  is_unix = RUBY_PLATFORM =~ /(aix|darwin|linux|(net|free|open)bsd|cygwin|solaris|irix|hpux)/i
  is_truffleruby = RUBY_DESCRIPTION =~ /truffleruby/
  gem "vterm", ">= 0.0.5" if is_unix && ENV['WITH_VTERM']
  gem "yamatanooroti", ">= 0.0.6"
  gem "rake"
  gem "stackprof" if is_unix && !is_truffleruby
  gem "test-unit"
  gem "reline", github: "ruby/reline" if ENV["WITH_LATEST_RELINE"] == "true"
  gem "debug", github: "ruby/debug"
end
