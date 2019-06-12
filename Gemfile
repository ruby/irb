source "https://rubygems.org"

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

gemspec

# TODO: remove this when reline with `Reline::Unicode.escape_for_print` is released.
if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7.0')
  gem "reline", github: "ruby/reline"
end
