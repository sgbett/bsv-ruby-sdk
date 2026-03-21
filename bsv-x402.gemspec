# frozen_string_literal: true

require_relative 'lib/bsv/x402/version'

Gem::Specification.new do |spec|
  spec.name    = 'bsv-x402'
  spec.version = BSV::X402::VERSION
  spec.authors = ['Simon Bettison']

  spec.summary     = 'BSV x402 Payment Required protocol middleware'
  spec.description = 'Rack middleware and client library implementing the x402 HTTP payment ' \
                     'protocol for BSV blockchain micropayments.'
  spec.homepage    = 'https://github.com/sgbett/bsv-ruby-sdk'
  spec.license     = 'LicenseRef-OpenBSV'

  spec.required_ruby_version = '>= 2.7'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/master/CHANGELOG.md",
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir.glob('lib/bsv/x402{.rb,/**/*}') + %w[lib/bsv-x402.rb LICENCE]
  spec.require_paths = ['lib']

  spec.add_dependency 'base64'
  spec.add_dependency 'bsv-sdk'
  spec.add_dependency 'rack', '>= 2.0'
end
