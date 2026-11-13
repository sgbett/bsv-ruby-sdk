# frozen_string_literal: true

source 'https://rubygems.org'

gem 'secp256k1-native', '~> 0.16'

gemspec path: 'gem/bsv-sdk'
gemspec path: 'gem/bsv-attest'

group :development, :test do
  gem 'rake'
  gem 'rspec'
  gem 'rubocop', '~> 1.92.0'
  gem 'rubocop-rspec', '~> 3.10.0'
  gem 'simplecov', require: false
  gem 'simplecov-cobertura', require: false
  gem 'yard'
  gem 'yard-markdown', '~> 0.10.0'

  gem 'benchmark-ips'
  gem 'prime'
  gem 'rack'
end
