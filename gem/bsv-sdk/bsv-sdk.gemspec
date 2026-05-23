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

  spec.required_ruby_version = '>= 3.3'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/master/gem/bsv-sdk/CHANGELOG.md",
    'rubygems_mfa_required' => 'true'
  }

  spec.bindir      = 'bin'
  spec.executables = ['bsv-mcp']

  # Dir.chdir(__dir__) makes the glob resolve relative to this gemspec,
  # not the working directory — so `gem build` works from any CWD.
  spec.files = Dir.chdir(__dir__) do
    Dir.glob('lib/**/*') +
      Dir.glob('bin/*')
  end + %w[LICENSE README.md CHANGELOG.md]
  spec.require_paths = ['lib']

  spec.add_dependency 'base64'
  spec.add_dependency 'mcp', '~> 0.15'
  spec.add_dependency 'secp256k1-native', '>= 0.16'
end
