# frozen_string_literal: true

require_relative 'lib/bsv/version'

Gem::Specification.new do |spec|
  spec.name    = 'bsv-sdk'
  spec.version = BSV::VERSION
  spec.authors = ['Simon Bettison']

  spec.summary     = 'Ruby SDK for the BSV Blockchain'
  spec.description = 'A Ruby library for interacting with the BSV Blockchain — ' \
                     'keys, scripts, transactions, and more.'
  spec.homepage    = 'https://github.com/sgbett/bsv-ruby-sdk'
  spec.license     = 'LicenseRef-OpenBSV'

  spec.required_ruby_version = '>= 2.7'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/master/CHANGELOG.md",
    'rubygems_mfa_required' => 'true'
  }

  # Explicit module list — bsv-attest and bsv-wallet are separate gems with
  # their own gemspecs and must not be bundled into bsv-sdk. Adding a new
  # top-level SDK module means adding it here AND to the autoload list in
  # lib/bsv-sdk.rb.
  spec.files = Dir.glob(
    'lib/bsv/{primitives,script,transaction,network,wallet,auth,overlay,identity,registry}{.rb,/**/*}'
  ) + %w[lib/bsv-sdk.rb lib/bsv/version.rb LICENSE README.md CHANGELOG.md]
  spec.require_paths = ['lib']
end
