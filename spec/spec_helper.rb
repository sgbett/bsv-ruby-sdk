# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  require 'simplecov-cobertura'
  SimpleCov.start do
    add_filter '/spec/'
    formatter SimpleCov::Formatter::CoberturaFormatter
  end
end

require 'bsv-sdk'

# Load support files (test helpers, shared contexts, etc.)
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
  config.define_derived_metadata(testnet: true) do |meta|
    meta[:skip] = 'testnet tests excluded (run with: bundle exec rspec --tag testnet)' unless ENV['BSV_TESTNET_WIF']
  end
  config.order = :random
  Kernel.srand config.seed
end
