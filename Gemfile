source "https://rubygems.org"

gemspec

is_unix = RUBY_PLATFORM =~ /(aix|darwin|linux|(net|free|open)bsd|cygwin|solaris|irix|hpux)/i
is_truffleruby = RUBY_DESCRIPTION =~ /truffleruby/

if is_unix && ENV['WITH_VTERM']
  gem "vterm", github: "ruby/vterm-gem"
  gem "yamatanooroti", github: "ruby/yamatanooroti", ref: "f6e47192100d6089f70cf64c1de540dcaadf005a"
end

gem "stackprof" if is_unix && !is_truffleruby

gem "reline", github: "ruby/reline" if ENV["WITH_LATEST_RELINE"] == "true"
gem "rake"
gem "test-unit"
gem "test-unit-ruby-core"

gem "rubocop"

gem "tracer" if !is_truffleruby
gem "debug", github: "ruby/debug", platforms: [:mri, :mswin]

if RUBY_VERSION >= "3.0.0" && !is_truffleruby
  gem "repl_type_completor"
end
