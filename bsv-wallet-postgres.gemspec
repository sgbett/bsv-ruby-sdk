# frozen_string_literal: true

require_relative 'lib/bsv/wallet_postgres/version'

Gem::Specification.new do |spec|
  spec.name    = 'bsv-wallet-postgres'
  spec.version = BSV::WalletPostgres::VERSION
  spec.authors = ['Simon Bettison']

  spec.summary     = 'PostgreSQL storage adapter for bsv-wallet'
  spec.description = 'Persistent Sequel/Postgres-backed BSV::Wallet::StorageAdapter ' \
                     'implementation for production BSV wallet deployments.'
  spec.homepage    = 'https://github.com/sgbett/bsv-ruby-sdk'
  spec.license     = 'LicenseRef-OpenBSV'

  spec.required_ruby_version = '>= 2.7'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/master/CHANGELOG-wallet-postgres.md",
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir.glob('lib/bsv/wallet_postgres{.rb,/**/*}') + %w[lib/bsv-wallet-postgres.rb LICENSE CHANGELOG-wallet-postgres.md]
  spec.require_paths = ['lib']

  # bsv-wallet-postgres is released alongside bsv-wallet; the floor rises
  # with every wallet security release. Matches the pinning style
  # bsv-wallet uses for its own bsv-sdk dependency.
  spec.add_dependency 'bsv-wallet', '>= 0.4.0', '< 1.0'
  spec.add_dependency 'pg', '~> 1'
  spec.add_dependency 'sequel', '~> 5'
end
