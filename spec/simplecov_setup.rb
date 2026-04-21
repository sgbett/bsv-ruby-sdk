# frozen_string_literal: true

require 'simplecov'
require 'simplecov-cobertura'

SimpleCov.root(File.expand_path('..', __dir__))
SimpleCov.configure do
  add_filter '/spec/'
  add_filter %r{/migrations/}

  track_files 'gem/*/lib/**/*.rb'

  formatter SimpleCov::Formatter::CoberturaFormatter
end
