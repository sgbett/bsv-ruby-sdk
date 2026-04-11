# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  require 'simplecov-cobertura'
  SimpleCov.start do
    add_filter '/spec/'
    formatter SimpleCov::Formatter::CoberturaFormatter
  end
end

require 'bsv-wallet-postgres'

require_relative '../../bsv-wallet/spec/support/shared_examples_for_storage_adapter'

Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
