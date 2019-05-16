#!/usr/bin/env bash

# as of 2019-05, Travis Rubies 2.4 and later have RubyGems 3.0.3 or later installed

set -eux

test_frozen_strings=$(ruby -e 'puts ((RUBY_ENGINE == "ruby" || RUBY_ENGINE == "jruby") && RUBY_VERSION > "2.4")')

if [[ $test_frozen_strings == "true" ]] ; then
  echo "NOTE: enabling frozen string literals"
  export RUBYOPT="--enable-frozen-string-literal --debug=frozen-string-literal"
fi

# Workaround for JRuby builds seeming to not generate this ragel machine
bundle exec rake lib/racc/grammar_file_scanner.rb

# Unset this variable because it adds a warning to JVM startup
unset _JAVA_OPTIONS

# Speed up JRuby startup for subprocess tests
export JRUBY_OPTS='--disable-gems --dev'

bundle exec rake test
bundle exec rake test_pure
