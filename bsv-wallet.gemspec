# frozen_string_literal: true

require_relative 'lib/bsv/wallet_interface/version'

Gem::Specification.new do |spec|
  spec.name    = 'bsv-wallet'
  spec.version = BSV::WalletInterface::VERSION
  spec.authors = ['Simon Bettison']

  spec.summary     = 'BRC-100 Wallet Interface for the BSV Blockchain'
  spec.description = 'Implements the BRC-100 standard wallet-to-application interface for the BSV Blockchain.'
  spec.homepage    = 'https://github.com/sgbett/bsv-ruby-sdk'
  spec.license     = 'LicenseRef-OpenBSV'

  spec.required_ruby_version = '>= 2.7'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/master/CHANGELOG-wallet.md",
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir.glob('lib/bsv/wallet_interface{.rb,/**/*}') + %w[lib/bsv-wallet.rb LICENSE CHANGELOG-wallet.md]
  spec.require_paths = ['lib']

  spec.add_dependency 'base64', '~> 0.2'

  # bsv-wallet and bsv-sdk are released in lockstep from the same
  # repository. The `~> 0.4` constraint this replaces was stale — it
  # allowed bsv-sdk 0.4.x–0.9.x, but wallet hasn't been tested against
  # anything below current (0.8.x) in months. Pinning the floor at
  # 0.8.2 ensures consumers installing bsv-wallet 0.3.4 (which ships
  # Floor raised with each paired release so consumers of bsv-wallet
  # also pick up the corresponding bsv-sdk correctness fixes.
  spec.add_dependency 'bsv-sdk', '>= 0.9.0', '< 1.0'
end
