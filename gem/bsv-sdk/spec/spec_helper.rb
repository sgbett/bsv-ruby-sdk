# frozen_string_literal: true

if ENV['COVERAGE'].to_s == 'true'
  require_relative '../../../spec/simplecov_setup'
  SimpleCov.command_name 'bsv-sdk'
  SimpleCov.start
end

require 'bsv-sdk'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

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
  config.define_derived_metadata(chaintracks_live: true) do |meta|
    meta[:skip] = 'chaintracks live tests excluded (run with: bundle exec rspec --tag chaintracks_live)'
  end
  config.filter_run_excluding integration: true unless ENV['BSV_INTEGRATION'].to_s == 'true'
  config.order = :random
  Kernel.srand config.seed
end
