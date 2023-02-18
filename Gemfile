source "https://rubygems.org"

gemspec

is_unix = RUBY_PLATFORM =~ /(aix|darwin|linux|(net|free|open)bsd|cygwin|solaris|irix|hpux)/i
is_truffleruby = RUBY_DESCRIPTION =~ /truffleruby/

if is_unix && ENV['WITH_VTERM']
  gem "vterm", ">= 0.0.5", github: "ruby/vterm-gem"
end

gem "reline", github: "ruby/reline" if ENV["WITH_LATEST_RELINE"] == "true"
gem "yamatanooroti", ">= 0.0.6", github: "ruby/yamatanooroti"
gem "rake"
gem "stackprof" if is_unix && !is_truffleruby
gem "test-unit"
gem "debug", github: "ruby/debug"
