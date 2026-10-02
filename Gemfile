# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

group :development, :test do
  gem 'minitest', '~> 6.0'
  gem 'rake', '~> 13.0'

  gem 'anthropic', '~> 1.69'
  gem 'openai', '~> 0.80'

  gem 'rubocop', '~> 1.91', require: false
  gem 'rubocop-minitest', '~> 0.40', require: false
  gem 'rubocop-performance', '~> 1.26', require: false
  gem 'rubocop-rake', '~> 0.7', require: false

  gem 'rbs', '~> 4.2', require: false
  gem 'rbs-inline', '~> 0.14', require: false
  gem 'steep', '~> 2.1', require: false

  gem 'guard'
  gem 'guard-shell'

  gem 'webrick', require: false

  gem 'kramdown', require: false
  gem 'kramdown-parser-gfm', require: false
  gem 'rdoc', require: false
  # kramdown's rouge integration trips deprecation warnings on rouge 5.
  gem 'rouge', '~> 4.6', require: false
end
