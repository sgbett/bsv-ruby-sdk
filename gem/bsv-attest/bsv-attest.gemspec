# frozen_string_literal: true

require_relative 'lib/bsv/attest/version'

Gem::Specification.new do |spec|
  spec.name    = 'bsv-attest'
  spec.version = BSV::Attest::VERSION
  spec.authors = ['Simon Bettison']

  spec.summary     = 'Data attestation for the BSV Blockchain'
  spec.description = 'Hash data, publish hashes to the BSV blockchain via OP_RETURN, ' \
                     'and verify attestations on chain.'
  spec.homepage    = 'https://github.com/sgbett/bsv-ruby-sdk'
  spec.license     = 'LicenseRef-OpenBSV'

  spec.required_ruby_version = '>= 2.7'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/master/gem/bsv-attest/CHANGELOG.md",
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir.chdir(__dir__) do
    Dir.glob('lib/**/*')
  end + %w[LICENSE CHANGELOG.md]
  spec.require_paths = ['lib']

  spec.add_dependency 'bsv-sdk'
end
